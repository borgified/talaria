# Talaria 🪽

**Talaria** is a lightweight Bash script and optimization suite designed to significantly reduce boot times on Ubuntu systems. Named after the winged sandals of Hermes, it strips away unnecessary background initialization delays and heavy daemon overhead to deliver an optimized, sub-10 second boot sequence.

## ⚡ Optimization Overview

The following optimization steps are sorted in order of greatest potential boot speed improvement:

| Rank | Optimization Step | Category | Estimated Time Saved | Description |
| :---: | :--- | :--- | :---: | :--- |
| **1** | **Mask Wait-Online Services** | Network Stack | ~15 – 30s | Masks `systemd-networkd-wait-online.service` and marks interfaces `optional: true` so systemd never blocks graphical targets waiting for network synchronization. |
| **2** | **Bridge Zero-Delay STP** | Network Bridges | ~15 – 30s | Sets bridge STP `forward-delay: 0` in Netplan to eliminate default Spanning Tree Protocol forwarding and listening delays. |
| **3** | **Purge Heavy Server Stacks** | Background Services | ~10 – 15s | Uninstalls monolithic daemons (e.g., GitLab Omnibus / `gitlab-runsvdir.service`) that spin up embedded databases (PostgreSQL, Redis) and monitoring engines at boot. |
| **4** | **Prune Unused Virtualization Daemons** | Hypervisor / KVM | ~5 – 10s | Disables and purges idle Libvirt/QEMU daemons (`libvirtd`, `virtlogd`, `libvirt-guests.service`) and default virtual bridges (`virbr0`). |
| **5** | **Static IP Transition** | DHCP / Netplan | ~2 – 5s | Transitions from DHCP to static IP assignments to bypass router discovery, request, and lease negotiation latencies. |
| **6** | **Disable Crash Reporting Services** | Diagnostic Daemons | ~1 – 3s | Disables non-essential diagnostic and error-reporting background daemons (`apport.service`, `kerneloops.service`, `whoopsie`). |
| **7** | **Systemd Unit & Target Cleanup** | Systemd Hygiene | ~0.5 – 1s | Removes orphaned unit files, deactivates lingering in-memory targets (such as `virt-guest-shutdown.target`), and resets failed units. |

## 🚀 The Problem
By default, Ubuntu's boot chain blocks on network synchronization and loads legacy or unused services into the critical startup path:
* **Blocking Network Daemons:** Ubuntu's network stack (`systemd-networkd`, Netplan) defaults to holding up graphical targets while waiting for DHCP handshakes and Spanning Tree Protocol (STP) listening loops. This alone can add 15 to 30 seconds of artificial delay before the desktop loads.
* **Heavy Daemon Sprawl:** Background packages like virtualization hypervisors, server orchestration runtimes, and crash collectors often hook into startup targets by default, competing for disk I/O and CPU cycles during the most critical boot phase.

## ✨ Optimization Details

Talaria groups optimizations into two major categories:

### 🌐 Network Stack Tuning
* **Non-Blocking Boot:** Masks `systemd-networkd-wait-online.service` and tags network interfaces as `optional: true` in Netplan so your graphical session starts immediately at hardware speed.
* **Bridge Zero-Delay:** Tunes bridge parameters (`forward-delay: 0`) to immediately transition virtual and physical bridge interfaces into forwarding state without waiting for network loop topology timers.
* **Static IP Transition:** Replaces sluggish DHCP lease requests with immediate static network bindings.

### 🧹 Service & Daemon Pruning (9/19 Session)
* **Monolithic Server Stack Elimination:** Stops and purges heavy all-in-one stacks like GitLab CE (`gitlab-runsvdir.service`), preventing background PostgreSQL, Redis, Puma, and Prometheus daemons from starting at boot.
* **Virtualization Stack De-provisioning:** Removes `qemu-kvm`, `libvirt-daemon-system`, and associated guest suspend/resume daemons (`libvirt-guests.service`), as well as tearing down unused virtual network bridges (`virbr0`).
* **Telemetry & Crash Reporter Disabling:** Bypasses non-essential reporting services like `apport.service` and `kerneloops.service` that hook into the critical startup chain.
* **Systemd Cleanup:** Removes orphaned unit files (such as dynamically generated `/usr/lib/systemd/system/gitlab-runsvdir.service`) and stops persistent in-memory targets (such as `virt-guest-shutdown.target`).

## 🛠️ Usage
Simply clone the repository and run the optimization script:

```bash
git clone https://github.com/borgified/talaria.git
cd talaria
sudo ./talaria.sh
```

## 📊 Performance Tracking
You can measure the exact impact of Talaria by inspecting the boot timeline:

```bash
# View overall firmware, kernel, and userspace boot duration
systemd-analyze time

# Inspect which services took the longest to start
systemd-analyze blame

# View the critical chain of dependent services delaying target graphical
systemd-analyze critical-chain
```

## 📄 License
This project is open-source and available under the [GNU General Public License v3.0](LICENSE).
