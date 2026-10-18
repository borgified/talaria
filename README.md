# Talaria 🪽

**Talaria** is a lightweight Bash script designed to significantly reduce boot times on Ubuntu systems. Named after the winged sandals of Hermes, it strips away unnecessary background initialization delays to deliver an optimized, sub-10 second boot sequence.

## 🚀 The Problem
By default, Ubuntu's network stack (`systemd-networkd`, Netplan) forces the operating system to pause during startup to execute DHCP handshakes and listen for network loops via Spanning Tree Protocol (STP) on bridge interfaces. This can add 15 to 30 seconds of artificial delay before you ever see your desktop.

## ✨ Features
Talaria automates critical system and network-level optimizations:
* **Static IP Transition:** Bypasses sluggish DHCP lease requests.
* **Bridge Zero-Delay:** Configures STP parameters (`forward-delay: 0`) to bring network bridges online instantly.
* **Non-Blocking Boot:** Marks interfaces as optional and disables the blocking `systemd-networkd-wait-online.service` so your desktop loads at pure hardware speed.

## 🛠️ Usage
Simply clone the repository and run the optimization script:

```bash
git clone https://github.com
cd talaria
sudo ./talaria.sh
```

## 📊 Performance Tracking
You can measure the exact impact of Talaria by running:
```bash
systemd-analyze blame
```

## 📄 License
This project is open-source and available under the [GNU General Public License v3.0](LICENSE).
