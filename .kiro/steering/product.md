# Product: ARX3000M Custom OpenWrt Firmware

Custom OpenWrt firmware build system targeting the **中移 RAX3000M** router (MediaTek MT7981B / Filogic 820, AX3000 WiFi6, 512MB RAM).

The project ships a set of custom LuCI packages and a theme that are compiled into the firmware image:

- **luci-theme-arx3000m** — Modern dark/light responsive theme with CSS variable system
- **luci-app-arx-dashboard** — Real-time system monitoring (CPU, memory, temperature, network, disk)
- **luci-app-arx-netmgr** — Device manager: ARP/DHCP list, block/unblock, IP-MAC binding, aliases
- **luci-app-arx-network** — Advanced networking: port forwarding, firewall rules, VPN/DDNS status, diagnostics
- **luci-app-arx-software** — Package/software source management
- **luci-app-arx-bridge** — Read-only WiFi uplink / bridge / relayd overview
- **luci-app-arx-wizard** — Setup wizard
- **luci-app-arx-wificrack** — WiFi handshake capture tool (hcxdumptool / airodump-ng / tcpdump)

Target hardware: `mediatek/filogic`, `aarch64_cortex-a53`, OpenWrt main branch.
