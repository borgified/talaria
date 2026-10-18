#!/usr/bin/env bash
# ==============================================================================
# Talaria 🪽 - Ubuntu Boot Speed Optimization Suite
# License: GNU General Public License v3.0 (GPLv3)
# Description: Progressive, staged systemd and network boot speed optimization.
# ==============================================================================

set -euo pipefail

VERSION="1.0.0"
BASELINE_LOG="/var/log/talaria_baseline.log"
USER_BASELINE_LOG="${HOME}/.talaria_baseline.log"

# Terminal Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ------------------------------------------------------------------------------
# Helper & Logging Functions
# ------------------------------------------------------------------------------
log_info() {
    echo -e "${CYAN}ℹ [INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}✔ [SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}⚠ [WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}✖ [ERROR]${NC} $1" >&2
}

log_header() {
    echo -e "\n${BOLD}${BLUE}=== $1 ===${NC}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This action requires root privileges. Please run with sudo:"
        echo -e "    sudo $0 $*\n"
        exit 1
    fi
}

get_baseline_path() {
    if [[ -f "$BASELINE_LOG" ]]; then
        echo "$BASELINE_LOG"
    elif [[ -f "$USER_BASELINE_LOG" ]]; then
        echo "$USER_BASELINE_LOG"
    elif [[ -f "${HOME}/boot_speed_report.txt" ]]; then
        echo "${HOME}/boot_speed_report.txt"
    else
        echo ""
    fi
}

# ------------------------------------------------------------------------------
# Safety Guardrails
# ------------------------------------------------------------------------------
enforce_safety_guardrails() {
    log_info "Verifying critical system and display manager services..."

    # NEVER mask accounts-daemon.service on desktop systems (causes GDM/GNOME hang at boot)
    local dangerous_services=("accounts-daemon.service" "systemd-logind.service" "gdm.service" "gdm3.service" "dbus.service")
    for svc in "${dangerous_services[@]}"; do
        local state
        state=$(systemctl is-enabled "$svc" 2>/dev/null || true)
        if [[ "$state" == "masked" ]]; then
            log_warn "CRITICAL SAFETY RISK DETECTED: '$svc' is masked!"
            log_warn "Masking '$svc' can cause desktop login managers (GDM) to hang at boot."
            read -r -p "Do you want Talaria to unmask '$svc' now? (Recommended: Y/n): " unmask_choice
            unmask_choice=${unmask_choice:-Y}
            if [[ "$unmask_choice" =~ ^[Yy]$ ]]; then
                systemctl unmask "$svc"
                systemctl enable "$svc" 2>/dev/null || true
                log_success "Unmasked and enabled '$svc'."
            fi
        fi
    done
}

# ------------------------------------------------------------------------------
# Stage 1: Quick Wins (Zero Risk - Network Wait-Online)
# ------------------------------------------------------------------------------
stage_1() {
    check_root
    log_header "Stage 1: Quick Wins (Zero Risk, Unblock Desktop Loading)"
    log_info "Masking blocking network wait-online services (~15-30s boot gain)..."

    local wait_services=("systemd-networkd-wait-online.service" "NetworkManager-wait-online.service")
    for svc in "${wait_services[@]}"; do
        if systemctl list-unit-files "$svc" &>/dev/null; then
            systemctl stop "$svc" 2>/dev/null || true
            systemctl mask "$svc" 2>/dev/null || true
            log_success "Masked $svc"
        else
            log_info "$svc not installed, skipping."
        fi
    done

    # Check Netplan files for optional flag
    if [[ -d /etc/netplan ]]; then
        log_info "Checking Netplan interfaces for 'optional: true'..."
        local netplan_files
        netplan_files=$(find /etc/netplan -name "*.yaml" -o -name "*.yml" 2>/dev/null || true)
        if [[ -n "$netplan_files" ]]; then
            log_info "Found Netplan configuration files:"
            echo "$netplan_files"
            log_info "Tip: Ensure non-critical physical interfaces specify 'optional: true' to avoid boot delays."
        fi
    fi

    log_success "Stage 1 completed successfully!"
}

# ------------------------------------------------------------------------------
# Stage 2: Background Timers & Telemetry (Low Risk)
# ------------------------------------------------------------------------------
stage_2() {
    check_root
    log_header "Stage 2: Background Timers & Telemetry Pruning (Low Risk)"
    log_info "Configuring daily update timers and disabling background telemetry (~5-10s gain)..."

    # 1. Delay APT daily timers
    log_info "Configuring randomized delay on apt-daily timers to prevent boot disk thrashing..."
    mkdir -p /etc/systemd/system/apt-daily.timer.d /etc/systemd/system/apt-daily-upgrade.timer.d
    
    cat << 'EOF' > /etc/systemd/system/apt-daily.timer.d/override.conf
[Timer]
RandomizedDelaySec=1h
Persistent=true
EOF

    cat << 'EOF' > /etc/systemd/system/apt-daily-upgrade.timer.d/override.conf
[Timer]
RandomizedDelaySec=1h
Persistent=true
EOF
    systemctl daemon-reload
    log_success "Applied randomized 1h delay override to apt-daily timers."

    # 2. Disable Firmware updater and news services
    local telemetry_services=(
        "motd-news.timer"
        "motd-news.service"
        "fwupd-refresh.timer"
        "fwupd-refresh.service"
        "fwupd.service"
        "apport.service"
        "kerneloops.service"
        "whoopsie.service"
    )

    for svc in "${telemetry_services[@]}"; do
        if systemctl list-unit-files "$svc" &>/dev/null; then
            systemctl stop "$svc" 2>/dev/null || true
            systemctl disable "$svc" 2>/dev/null || true
            log_success "Disabled $svc"
        fi
    done

    log_success "Stage 2 completed successfully!"
}

# ------------------------------------------------------------------------------
# Stage 3: Bridge Zero-Delay & Static IP (Moderate Risk)
# ------------------------------------------------------------------------------
stage_3() {
    check_root
    log_header "Stage 3: Bridge Zero-Delay & Static IP Tuning (Moderate Risk)"
    
    # 1. Inspect Bridges in Netplan
    if [[ -d /etc/netplan ]]; then
        log_info "Searching for bridge configurations in Netplan..."
        local bridge_found=false
        while IFS= read -r file; do
            if grep -q "bridges:" "$file" 2>/dev/null; then
                bridge_found=true
                log_info "Found bridge configuration in $file"
                if grep -q "forward-delay: 0" "$file"; then
                    log_success "Bridge in $file already configured with 'forward-delay: 0'."
                else
                    log_warn "Bridge detected without 'forward-delay: 0'. Default STP delays can take 15-30s."
                    read -r -p "Would you like Talaria to back up $file and set forward-delay: 0? (y/N): " set_stp
                    if [[ "$set_stp" =~ ^[Yy]$ ]]; then
                        cp "$file" "${file}.bak_talaria_$(date +%s)"
                        sed -i '/parameters:/a \        forward-delay: 0' "$file" 2>/dev/null || true
                        log_success "Backup created and forward-delay set. Run 'sudo netplan apply' to test."
                    fi
                fi
            fi
        done < <(find /etc/netplan -name "*.yaml" -o -name "*.yml" 2>/dev/null)

        if [[ "$bridge_found" == false ]]; then
            log_info "No bridge interfaces found in Netplan."
        fi
    fi

    # 2. Static IP Transition Check
    log_info "Checking network interface addressing (DHCP vs Static)..."
    if ip route | grep -q "proto dhcp"; then
        log_info "Active DHCP lease detected on default route."
        echo -e "    ${YELLOW}Tip:${NC} Switching to static IP in Netplan bypasses DHCP discovery, saving ~2-5s on boot."
    else
        log_success "System is already using static IP configuration on default route."
    fi

    log_success "Stage 3 completed successfully!"
}

# ------------------------------------------------------------------------------
# Stage 4: Snapd & Heavy Daemon Cleanup (User-Confirmed)
# ------------------------------------------------------------------------------
stage_4() {
    check_root
    log_header "Stage 4: Snapd & Heavy Daemon Cleanup (User-Confirmed)"

    # 1. Snap & Snapd Check
    if command -v snap &>/dev/null; then
        log_warn "Snap is currently installed on this system."
        echo "Currently installed snaps:"
        snap list || true
        echo ""
        read -r -p "Do you want to inspect Firefox migration and snapd removal? (y/N): " handle_snap
        if [[ "$handle_snap" =~ ^[Yy]$ ]]; then
            echo -e "${CYAN}Instructions to migrate Firefox from Snap to Mozilla native APT:${NC}"
            echo "1. Run: sudo snap remove firefox"
            echo "2. Add Mozilla APT repo and pinning (/etc/apt/preferences.d/mozilla)"
            echo "3. Run: sudo apt install firefox"
            echo "4. When all snaps are removed, purge snapd: sudo apt purge snapd"
        fi
    else
        log_success "Snap / snapd is not installed (system is free of /dev/loop* snap mounts)!"
    fi

    # 2. Heavy Server / Virtualization Stacks
    local heavy_services=("gitlab-runsvdir.service" "libvirtd.service" "virtlogd.service" "libvirt-guests.service")
    local found_heavy=false
    for svc in "${heavy_services[@]}"; do
        if systemctl is-active --quiet "$svc" 2>/dev/null || systemctl is-enabled --quiet "$svc" 2>/dev/null; then
            found_heavy=true
            log_warn "Active heavy service detected: $svc"
        fi
    done

    if [[ "$found_heavy" == true ]]; then
        read -r -p "Do you want to stop and disable detected server/virtualization daemons? (y/N): " stop_heavy
        if [[ "$stop_heavy" =~ ^[Yy]$ ]]; then
            for svc in "${heavy_services[@]}"; do
                systemctl stop "$svc" 2>/dev/null || true
                systemctl disable "$svc" 2>/dev/null || true
                log_success "Stopped and disabled $svc"
            done
            # Check for virbr0
            if ip link show virbr0 &>/dev/null; then
                ip link delete virbr0 2>/dev/null || true
                log_success "Deleted virtual bridge virbr0"
            fi
        fi
    else
        log_success "No heavy background server stacks (GitLab / Libvirt) active."
    fi

    log_success "Stage 4 completed successfully!"
}

# ------------------------------------------------------------------------------
# Stage 5: Systemd Hygiene & Safety Enforcement
# ------------------------------------------------------------------------------
stage_5() {
    check_root
    log_header "Stage 5: Systemd Hygiene & Safety Enforcement"

    # 1. Stop lingering in-memory targets
    local lingering_targets=("virt-guest-shutdown.target")
    for tgt in "${lingering_targets[@]}"; do
        if systemctl is-active --quiet "$tgt" 2>/dev/null; then
            log_info "Stopping in-memory lingering target: $tgt"
            systemctl stop "$tgt" 2>/dev/null || true
            log_success "Stopped $tgt"
        fi
    done

    # 2. Clean orphaned unit files
    if [[ -f /usr/lib/systemd/system/gitlab-runsvdir.service ]] && ! dpkg -S /usr/lib/systemd/system/gitlab-runsvdir.service &>/dev/null; then
        log_info "Removing orphaned unowned unit: /usr/lib/systemd/system/gitlab-runsvdir.service"
        rm -f /usr/lib/systemd/system/gitlab-runsvdir.service
    fi

    # 3. Reload systemd and clear failed units
    log_info "Reloading systemd daemon and resetting failed units..."
    systemctl daemon-reload
    systemctl reset-failed

    # 4. Enforce Safety Guardrails
    enforce_safety_guardrails

    log_success "Stage 5 completed successfully!"
}

# ------------------------------------------------------------------------------
# Benchmarking Engine (--benchmark-pre, --diff, --status)
# ------------------------------------------------------------------------------
benchmark_pre() {
    local target_file="$BASELINE_LOG"
    if [[ $EUID -ne 0 ]]; then
        target_file="$USER_BASELINE_LOG"
    fi

    log_header "Capturing Pre-Optimization Baseline Benchmark"
    log_info "Writing baseline metrics to $target_file..."

    {
        echo "=== Talaria Baseline Benchmark Snapshot ==="
        echo "Captured: $(date -R)"
        echo ""
        echo "--- systemd-analyze time ---"
        systemd-analyze time 2>&1 || true
        echo ""
        echo "--- Critical Chain ---"
        systemd-analyze critical-chain 2>&1 || true
        echo ""
        echo "--- Top 25 Slowest Services (Blame) ---"
        systemd-analyze blame 2>&1 | head -n 25 || true
    } > "$target_file"

    log_success "Baseline recorded to $target_file!"
    echo -e "\n${BOLD}Baseline Summary:${NC}"
    systemd-analyze time || true
}

diff_benchmarks() {
    local baseline_path
    baseline_path=$(get_baseline_path)

    if [[ -z "$baseline_path" ]]; then
        log_error "No baseline benchmark found!"
        echo "Please record a baseline before optimizing using:"
        echo "    sudo $0 --benchmark-pre"
        exit 1
    fi

    log_header "Boot Performance Comparison vs Baseline"
    log_info "Baseline source: $baseline_path"

    echo -e "\n${BOLD}${CYAN}--- Baseline Timing ---${NC}"
    grep -E "Startup finished|graphical.target" "$baseline_path" || head -n 5 "$baseline_path"

    echo -e "\n${BOLD}${GREEN}--- Current Boot Timing ---${NC}"
    systemd-analyze time || true

    echo -e "\n${BOLD}Current Critical Chain:${NC}"
    systemd-analyze critical-chain 2>&1 | head -n 12 || true
}

show_status() {
    log_header "Talaria Optimization System Status"

    get_service_state() {
        local s="$1"
        local st
        st=$(systemctl is-enabled "$s" 2>/dev/null || true)
        if [[ -z "$st" ]]; then
            echo "not installed"
        else
            echo "$st"
        fi
    }

    echo -e "${BOLD}1. Network Wait-Online Services:${NC}"
    for s in systemd-networkd-wait-online.service NetworkManager-wait-online.service; do
        printf "   %-40s: %s\n" "$s" "$(get_service_state "$s")"
    done

    echo -e "\n${BOLD}2. Background Timers & News:${NC}"
    for s in apt-daily.timer apt-daily-upgrade.timer motd-news.timer fwupd-refresh.timer; do
        printf "   %-40s: %s\n" "$s" "$(get_service_state "$s")"
    done

    echo -e "\n${BOLD}3. Telemetry & Crash Reporters:${NC}"
    for s in apport.service kerneloops.service whoopsie.service; do
        printf "   %-40s: %s\n" "$s" "$(get_service_state "$s")"
    done

    echo -e "\n${BOLD}4. Package Managers (Snap):${NC}"
    if command -v snap &>/dev/null; then
        printf "   %-40s: %s\n" "snapd" "installed ($(snap list 2>/dev/null | tail -n +2 | wc -l) packages)"
    else
        printf "   %-40s: %b\n" "snapd" "${GREEN}purged (no loop mounts)${NC}"
    fi

    echo -e "\n${BOLD}5. Safety Guardrail Verification:${NC}"
    printf "   %-40s: %s\n" "accounts-daemon.service" "$(get_service_state accounts-daemon.service)"
    printf "   %-40s: %s\n" "systemd-logind.service" "$(get_service_state systemd-logind.service)"

    echo ""
}

show_usage() {
    cat << EOF
Talaria 🪽 v${VERSION} - Ubuntu Boot Speed Optimization Suite

Usage: sudo $0 [OPTION]

Progressive Stages:
    --stage 1          Stage 1: Quick wins (Zero risk, mask wait-online services)
    --stage 2          Stage 2: Background timers & telemetry pruning
    --stage 3          Stage 3: Network bridge zero-delay & static IP tuning
    --stage 4          Stage 4: Snapd & heavy daemon cleanup (Interactive)
    --stage 5          Stage 5: Systemd hygiene & safety check
    --safe             Run all safe, non-destructive stages (Stages 1, 2, and 5)

Benchmarking & Diagnostics:
    --benchmark-pre    Record a pre-optimization baseline to disk
    --diff             Compare current boot performance against baseline
    --status           Inspect current optimization state across all stages
    -h, --help         Show this help menu

Examples:
    sudo $0 --benchmark-pre     # 1. Save baseline before making changes
    sudo $0 --safe              # 2. Apply all safe quick-win optimizations
    sudo reboot                 # 3. Reboot system
    $0 --diff                   # 4. View performance delta and seconds saved
EOF
}

# ------------------------------------------------------------------------------
# Main Dispatcher
# ------------------------------------------------------------------------------
main() {
    if [[ $# -eq 0 ]]; then
        show_usage
        exit 0
    fi

    case "$1" in
        --stage)
            if [[ $# -lt 2 ]]; then
                log_error "Please specify a stage number (1-5)."
                exit 1
            fi
            case "$2" in
                1) stage_1 ;;
                2) stage_2 ;;
                3) stage_3 ;;
                4) stage_4 ;;
                5) stage_5 ;;
                *) log_error "Invalid stage: $2 (Must be 1, 2, 3, 4, or 5)"; exit 1 ;;
            esac
            ;;
        --safe)
            stage_1
            stage_2
            stage_5
            log_header "All Safe Stages Completed!"
            echo -e "${GREEN}Quick wins, timer optimizations, and hygiene checks applied.${NC}"
            echo -e "Reboot your system to experience the faster boot speed: ${BOLD}sudo reboot${NC}\n"
            ;;
        --benchmark-pre)
            benchmark_pre
            ;;
        --diff)
            diff_benchmarks
            ;;
        --status)
            show_status
            ;;
        -h|--help)
            show_usage
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
