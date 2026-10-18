# Talaria 🪽

**Talaria** is a modular, staged Bash optimization suite designed to significantly reduce boot times on Ubuntu systems by stripping away unnecessary background initialization delays, blocking network wait loops, and heavy daemon overhead.

> [!NOTE]
> **Tested Environment & Performance Expectations:** Tested and validated on **Ubuntu 24.04 LTS (Noble Numbat)** (specifically **Ubuntu 24.04.5 LTS**, Linux Kernel `6.8.0-146-generic`, systemd 255). Compatible with modern Ubuntu releases including 22.04 LTS and 24.04 LTS+.
> 
> *Hardware Dependency:* Sub-10s boot times (`graphical.target @ ~7.4s` on our test machine) depend heavily on underlying hardware (NVMe/SSD throughput, CPU, UEFI initialization, and peripheral buses). Absolute timings will vary; performance figures should be treated as comparative benchmarks rather than universal guarantees.

> [!IMPORTANT]
> ### 💾 Hardware Foundation: NVMe / SSD as Your Boot Drive
> **The single greatest speed improvement you can make to boot time is hardware.**
> Before applying software tweaks or running optimization scripts, ensure your root filesystem (`/`) is installed on a solid-state drive (**NVMe M.2 or SATA SSD**):
> * **Mechanical Hard Drives (HDDs):** Due to rotational latency and slow random 4K read speeds, Ubuntu booting from a mechanical hard drive typically takes **45 to 90+ seconds**. No amount of software tuning can overcome physical disk seek limitations.
> * **NVMe / SSDs:** Moving your OS to an SSD yields an immediate, massive **30 to 60+ second reduction** in boot time.
> * Talaria's software optimizations are designed to build upon an SSD foundation to eliminate the remaining network, daemon, and userspace stalls.

---

## ⚡ Staged Optimization Overview

Talaria runs in **progressive stages**, prioritizing **high-confidence quick wins** with zero risk of breakage first, leaving deeper package removals and network reconfigurations for user-confirmed stages:

| Stage | Optimization Action | Risk Level | Est. Time Saved | Description |
| :---: | :--- | :--- :---: | :---: | :--- |
| **Foundation** | **NVMe / SSD Boot Drive** | 💾 Hardware | **~30 – 60s+** | Moving Ubuntu from a mechanical HDD to an NVMe or SATA SSD removes mechanical seek times and 4K random read bottlenecks before running software tweaks. |
| **Stage 1** | **Mask Wait-Online Services** | 🟢 Zero Risk | **~15 – 30s** | Masks `systemd-networkd-wait-online` and `NetworkManager-wait-online`, marking interfaces `optional: true` so graphical boot never halts waiting for network connectivity. |
| **Stage 2** | **Tuning Background Timers & Telemetry** | 🟢 Low Risk | **~5 – 10s** | Re-schedules `apt-daily` timers to prevent boot-time disk thrashing; disables crash telemetry (`apport`, `whoopsie`), firmware polling (`fwupd`), and `motd-news`. |
| **Stage 3** | **Bridge Zero-Delay & Static IP** | 🟡 Moderate | **~15 – 30s** *(if bridges present)*<br>**~2 – 5s** *(DHCP)* | Sets bridge STP `forward-delay: 0` in Netplan to eliminate Spanning Tree Protocol listening delays; transitions DHCP interfaces to static IP addressing. |
| **Stage 4** | **Snapd & Heavy Stack Pruning** | 🟠 Requires Review | **~10 – 20s** | Eliminates snapd's heavy boot-time application update verification by transitioning Firefox to native APT (`apt-get`) with pinning, then purging `snapd`, `/dev/loop*` mounts, and idle server stacks (GitLab, KVM/Libvirt). |
| **Stage 5** | **Systemd Hygiene & Safety Guardrails** | 🟢 Low Risk | **~0.5 – 1s** | Deactivates lingering in-memory units (e.g. `virt-guest-shutdown.target`); removes orphaned unit files; actively guards against dangerous service masks. |

---

## 🛡️ Critical Safety Guardrails

> [!CAUTION]
> **Never mask `accounts-daemon.service` on Desktop Ubuntu!**
> While `accounts-daemon` may show up in `systemd-analyze blame`, masking it breaks GDM/GNOME user enumeration and causes the system to hang at boot on the filesystem check (e.g., `/dev/mapper/... clean`). Talaria includes an active guardrail that forbids masking this or any critical display manager dependencies.

---

## 🚀 The Problem
By default, Ubuntu's boot chain blocks on network synchronization and loads legacy or unused background services into the critical startup path:
1. **Blocking Network Daemons:** Ubuntu's network stack defaults to pausing the desktop load while waiting for DHCP handshakes and Spanning Tree Protocol (STP) listening loops. This alone can add 15 to 30 seconds of artificial delay.
2. **Heavy Daemon Sprawl & Snapd Update Checks:** By default, `snapd` mounts individual virtual disk loop devices (`/dev/loop*`) for every package and spends significant time verifying that installed snap applications are up to date on boot. Monolithic stacks (like virtualization hypervisors or server runtimes) compete for disk I/O and CPU cycles during early userspace initialization.

---

## ✨ The 5 Optimization Stages

### 🟢 Stage 1: Quick Wins (Zero Risk, Immediate Desktop Access)
* **Mask Blocking Wait Services:** Masks `systemd-networkd-wait-online.service` and `NetworkManager-wait-online.service`.
* **Non-Blocking Netplan Defaults:** Ensures network interfaces are tagged `optional: true` so graphical targets load at raw hardware speed.

### 🟢 Stage 2: Background Timers & Telemetry Pruning (Low Risk)
* **Delay Daily APT Timers:** Configures `apt-daily.timer` and `apt-daily-upgrade.timer` with a randomized boot delay so they do not hammer your disk and CPU the second you log in.
* **Disable Hardware & News Polling:** Disables `fwupd.service`, `fwupd-refresh.service`, and `motd-news.timer`.
* **Disable Crash Telemetry:** Disables non-essential diagnostic collectors: `apport.service`, `kerneloops.service`, and `whoopsie.service`.

### 🟡 Stage 3: Bridge Zero-Delay & Static IP (Network-Dependent)
* **Bridge Zero-Delay STP:** Tunes bridge parameters (`forward-delay: 0`) in Netplan to immediately bring network bridges into the forwarding state without waiting out the 30-second STP listening/learning loop.
* **Static IP Transition:** Replaces DHCP lease requests with static bindings to eliminate router handshake latencies during early boot.

### 🟠 Stage 4: Package & Heavy Stack Pruning (High Impact, User-Confirmed)
* **Snapd Elimination (Removing the Update Timesink):**
  * One of the largest timesinks on Ubuntu boot is `snapd` verifying that every installed snap application is up to date, alongside mounting virtual loop filesystems for each snap.
  * Checks for installed snaps (`snap list`).
  * If Firefox is present, migrates profile data to native Mozilla APT via `apt-get` with official repository version pinning (`/etc/apt/preferences.d/mozilla`), allowing full browser functionality without snapd.
  * Once migrated, purges `snapd`, permanently removing background update polling and all `/dev/loop*` virtual disk mounts.
* **Server & Hypervisor Stack Purge:** Stops and purges unused heavyweight stacks (e.g. GitLab CE `gitlab-runsvdir.service`, `qemu-kvm`, `libvirt-daemon-system`, and default bridge `virbr0`).

### 🟢 Stage 5: Systemd Hygiene & Safety Enforcement
* **Target & Unit Cleanup:** Stops and clears lingering in-memory units (such as orphaned `virt-guest-shutdown.target`), cleans up dynamic unit leftovers, and runs `systemctl daemon-reload` and `systemctl reset-failed`.
* **Guardrail Enforcement:** Verifies that no critical desktop services (`accounts-daemon`, `systemd-logind`, `gdm3`) are accidentally masked or disabled.

---

## 🛠️ Usage

Clone the repository and run Talaria:

```bash
git clone https://github.com/borgified/talaria.git
cd talaria
chmod +x talaria.sh
```

### 1. Progressive Stage Execution

Run individual stages or all safe stages progressively:

```bash
# Check current system status and detect potential bottlenecks
sudo ./talaria.sh --status

# Stage 1: Quick wins only (Zero risk, unblocks network wait)
sudo ./talaria.sh --stage 1

# Stage 2: Timers & telemetry (Low risk)
sudo ./talaria.sh --stage 2

# Stage 3: Bridge zero-delay tuning (Netplan)
sudo ./talaria.sh --stage 3

# Stage 4: Snapd & heavy stack cleanup (Interactive confirmation)
sudo ./talaria.sh --stage 4

# Stage 5: Systemd hygiene & safety check
sudo ./talaria.sh --stage 5

# Or run all safe stages (Stages 1, 2, and 5) automatically:
sudo ./talaria.sh --safe
```

---

## 📊 Performance Tracking & Reboot Benchmarks

Talaria includes automated before/after benchmark tracking across reboots so you can objectively measure your performance gains.

### 🔄 The Reboot Verification Workflow

Because reboots clear memory, Talaria uses persistent filesystem breadcrumbs to track and validate speed gains:

1. **Pre-Optimization Snapshot:** Before applying any changes, record a baseline of your startup performance:
   ```bash
   sudo ./talaria.sh --benchmark-pre
   # Automatically captures systemd-analyze time, blame, and critical-chain to /var/log/talaria_baseline.log
   ```
2. **Apply Optimizations & Reboot:** Run your desired stages and reboot:
   ```bash
   sudo ./talaria.sh --safe
   sudo reboot
   ```
3. **Post-Reboot Delta Comparison:** After logging back in, diff against the baseline:
   ```bash
   ./talaria.sh --diff
   # Calculates exact seconds saved across firmware, kernel, loader, and userspace
   ```

### 🔍 Manual Inspection Commands
You can also inspect the boot timeline directly at any time:

```bash
# View overall firmware, kernel, and userspace boot duration
systemd-analyze time

# Inspect which services took the longest to start
systemd-analyze blame

# View the critical chain of dependent services delaying target graphical
systemd-analyze critical-chain
```

---

## 📄 License
This project is open-source and available under the [GNU General Public License v3.0](LICENSE).
