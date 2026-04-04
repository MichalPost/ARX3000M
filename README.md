# ARX3000M OpenWrt 自定义固件工程

## 项目概述

为 **中移 RAX3000M**（MT7981B Filogic 820）路由器定制的一套 OpenWrt 固件编译工程，包含：

- 🎨 **自定义 LuCI 主题** - 现代化深色/浅色双主题，响应式设计
- 📊 **系统监控仪表盘** - CPU、内存、温度、网络流量实时监控
- 📡 **设备管理器** - 在线设备列表、屏蔽/解封、IP-MAC 绑定
- 🌐 **高级网络工具** - 端口转发、防火墙规则、VPN/DDNS 状态、网络诊断

## 硬件规格

| 项目 | 规格 |
|------|------|
| SoC | 联发科 MT7981B (Filogic 820), 双核 A53 @1.3GHz |
| 内存 | 512MB DDR4 |
| 闪存 | 128MB NAND / 64GB eMMC (算力版) |
| 无线 | AX3000 WiFi6 (MT7976CN) |
| OpenWrt 目标平台 | `mediatek/filogic` |

## 目录结构

```
ARX3000M/
├── build.sh                  # 编译主脚本 (一键操作)
├── setup-env.sh              # 编译环境搭建脚本
├── config/
│   └── rax3000m.config       # 完整 .config 预配置
├── theme/                    # 自定义 LuCI 主题
│   ├── Makefile
│   ├── htdocs/
│   │   ├── css/style.css     # 主题样式 (深色/浅色)
│   │   └── js/arx.js         # 主题交互逻辑
│   └── luasrc/view/themes/arx3000m/
│       ├── header.htm        # 页面头部模板
│       └── footer.htm        # 页面底部模板
└── packages/
    ├── luci-app-arx-dashboard/   # 系统监控仪表盘
    │   ├── Makefile
    │   ├── luasrc/controller/    # 后端控制器 (JSON API)
    │   ├── luasrc/view/          # 前端页面 (HTML+JS)
    │   └── root/usr/share/rpcd/acl.d/  # 权限控制
    ├── luci-app-arx-netmgr/      # 网络/设备管理
    │   ├── Makefile
    │   ├── luasrc/controller/
    │   ├── luasrc/model/cbi/     # CBI 表单模型
    │   ├── luasrc/view/
    │   └── root/etc/config/      # UCI 配置
    ├── luci-app-arx-network/     # 高级网络功能
    │   ├── Makefile
    │   ├── luasrc/controller/
    │   ├── luasrc/model/cbi/
    │   └── luasrc/view/
    └── luci-app-arx-software/  # 软件源 / 包管理
        ├── Makefile
        ├── luasrc/controller/
        └── luasrc/view/
```

## 🚀 GitHub Actions 自动编译 (推荐)

无需本地 Linux 环境，直接在 GitHub 上自动编译固件！

### 使用方法

```bash
# 1. 初始化 Git 仓库并推送
cd /path/to/ARX3000M
git init
git add .
git commit -m "feat: ARX3000M OpenWrt custom firmware"
git branch -M main
git remote add origin https://github.com/<你的用户名>/arx3000m-openwrt.git
git push -u origin main

# 2. 推送后，GitHub Actions 自动开始编译
#    访问: https://github.com/<你的用户名>/arx3000m-openwrt/actions 查看进度

# 3. 编译完成后 (约 30-60 分钟)，下载产物:
#    - Actions 页面 → 对应 run → Artifacts → 下载 arx3000m-firmware-xxx.zip
#    - 或 Release 页面 (main 分支自动创建) → 下载 .bin 文件
```

### 手动触发编译

除了 push 自动触发，还可以手动运行：

1. 进入 **Actions** 页面
2. 选择 **Build ARX3000M OpenWrt Firmware**
3. 点击 **Run workflow**
4. 可选参数：
   - **target**: 编译目标（默认 `mediatek/filogic`）
   - **upload_release**: 是否上传到 Release（仅 main 分支生效）

### CI 流程说明

```
┌─────────────┐     ┌─────────────┐     ┌──────────────┐
│  准备环境     │ ──▶ │  编译固件     │ ──▶ │  发布 Release │
│             │     │             │     │              │
│ · 缓存 dl   │     │ · 安装依赖   │     │ · 创建 Tag   │
│ · 缓存ccache│     │ · 克隆源码   │     │ · 上传 bin   │
│ · 生成Key   │     │ · 复制自定义包│     │ · 清理旧版   │
│             │     │ · feeds更新  │     │              │
│             │     │ · make V=s   │     │              │
└─────────────┘     └─────────────┘     └──────────────┘
```

### CI 特性

| 特性 | 说明 |
|------|------|
| **缓存加速** | dl 目录 + ccache 双缓存，二次编译提速 50%+ |
| **并发控制** | 同一分支多次 push 自动取消旧的 |
| **超时保护** | 单次编译最长 120 分钟 |
| **日志保留** | 构建日志自动打包为 Artifact，保留 7 天 |
| **自动发布** | main 分支 push 自动创建 GitHub Release |
| **版本管理** | 格式 `v1.0.<run_id>-<日期>`，自动清理旧版本（保留最新 5 个） |

### 自定义配置修改

如果你想调整 `.config` 编译选项：

1. 本地编译一次：`./build.sh build`
2. 导出精简差异：`./build.sh diffconfig`（输出到 `config/rax3000m.diffconfig.min`）
3. 将需要的选项合并进 `config/rax3000m.config`（或直接在完整预置文件中编辑）
4. `git push` 触发重新编译

## 快速开始

### 方式一：GitHub Actions 自动编译 (推荐 ⭐) 👆 见上方

### 方式二：使用 build.sh 一键本地编译

```bash
# 1. 将此项目放到 Linux 环境 (Ubuntu 22.04+, WSL2 也行)
cd /path/to/ARX3000M

# 2. 初始化环境 (安装依赖 + 拉取 OpenWrt 源码)
chmod +x build.sh setup-env.sh
./build.sh init

# 3. 复制自定义包到 OpenWrt 目录
./build.sh copy

# 4. 更新 feeds 并加载预配置
./build.sh feed
./build.sh config

# 5. 开始编译 (根据 CPU 核心数自动并行)
./build.sh build
```

### 方式二：手动步骤

```bash
# 1. 安装编译依赖 (Ubuntu)
sudo apt-get update
sudo apt-get install -y build-essential ccache ecj fastjar file g++ gcc \
    java-jdk git libncurses5-dev libssl-dev python3-distutils \
    python3-pyelftools python3-setuptools rsync subversion swig unzip \
    wget zlib1g-dev curl python3-full flex bison gettext libelf-dev \
    autoconf automake libtool binutils patch quilt re2c xsltproc zstd

# 2. 克隆 OpenWrt 源码
mkdir -p ~/openwrt-build && cd ~/openwrt-build
git clone https://github.com/openwrt/openwrt.git --depth 1 --branch main
cd openwrt

# 3. 复制自定义包
mkdir -p package/custom
cp -r /path/to/ARX3000M/packages/* package/custom/
cp -r /path/to/ARX3000M/theme package/custom/luci-theme-arx3000m

# 4. 更新 feeds
./scripts/feeds update -a
./scripts/feeds install -a

# 5. 加载预配置
cp /path/to/ARX3000M/config/rax3000m.config .config
make defconfig

# 6. 下载源码包
make download -j$(nproc)

# 7. 编译 (V=s 显示详细日志，方便排查问题)
make -j$(nproc) V=s
```

## 编译产物

编译完成后，固件文件位于：
```
bin/targets/mediatek/filogic/
├── openwrt-mediatek-filogic-xiaomi_redmi-router-ax6s-squashfs-sysupgrade.bin  # 升级固件
├── openwrt-mediatek-filogic-xiaomi_redmi-router-ax6s-squashfs-factory.bin     # 工厂固件
└── ...
```

> **注意**: RAX3000M 的 sysupgrade 固件可以直接通过 LuCI 或 SSH 升级刷入。

## 功能模块详解

### 1. Dashboard (系统仪表盘)
- **路径**: 服务 → Dashboard
- **功能**:
  - 6 个实时状态卡片：CPU / 内存 / 网络 / 温度 / 运行时间 / 磁盘（含阈值说明与网络健康摘要）
  - 刷新间隔由 `/etc/config/arx-dashboard` 控制（默认 `poll_realtime_sec` 约 10 秒）；页面在后台标签时会按 `hidden_poll_multiplier` 降频，减轻 CGI 压力
  - 系统信息表（型号、内核、固件版本等）
  - 网络接口流量统计表
  - 进度条可视化资源占用

#### 监控数据源说明（collectd 与仪表盘）

- 预置配置可启用 **collectd**（周期性写 RRD，开销相对较低），用于长期统计与部分 LuCI 图表。
- **ARX 仪表盘**仅在打开管理页面时通过 CGI 轮询 JSON；二者可同时存在，前台高频轮询对 CPU/闪存压力更明显。
- 若设备为 **512MB RAM** 等小内存环境，建议优先调大 `poll_*` 间隔、避免多页同时常开自动刷新，而不是强制关闭 collectd（除非确认不需要历史统计）。

### 2. Network Manager (设备管理)
- **路径**: 服务 → Network Manager
- **功能**:
  - ARP 表 + DHCP 租约合并展示
  - 设备搜索和过滤（WiFi/有线/已屏蔽）
  - 一键屏蔽/解封设备（iptables + DHCP 层）
  - IP-MAC 静态绑定管理（CBI 表单）
  - 设备别名、分组（家人 / IoT / 未分类）持久化至 UCI；详情页可编辑
  - 指向 SQM / EQoS 的快捷入口（需固件已安装对应 LuCI 插件）
  - 设备详情查看（厂商、活跃连接数）
  - WiFi 信号强度显示

### 3. Network Tools (高级网络)
- **路径**: 服务 → Network Tools
- **功能**:
  - VPN 状态总览（WireGuard/OpenVPN）
  - DDNS 动态 DNS 服务状态
  - UPnP/NAT-PMP 映射状态
  - 端口转发规则管理（CBI 表单）
  - 防火墙规则编辑器（支持 INPUT/FORWARD/OUTPUT/PREROUTING/POSTROUTING）
  - Ping / Traceroute / NSLookup / Netstat 诊断工具
  - 一键导出脱敏诊断包（与仪表盘「网络健康」同源数据时建议一并安装 `luci-app-arx-dashboard`）

## 自定义主题说明

主题采用 CSS 变量系统，支持深色/浅色模式切换。未点击过主题菜单时，亮/暗会跟随系统 **prefers-color-scheme**；在顶栏主题选择器中点选任意主题后，将记住为手动选择并停止自动跟随系统。

```css
/* 主要颜色 */
--primary: #6366f1;      /* 主色调 - 靛蓝 */
--accent: #06b6d4;        /* 强调色 - 青色 */
--success: #10b981;       /* 成功 */
--warning: #f59e0b;       /* 警告 */
--danger: #ef4444;        /* 危险 */

/* 修改颜色只需改 :root 变量即可全局生效 */
```

## 常见问题

### Q: 编译报错怎么办？
A: 查看 `build.log` 文件中的错误信息。常见原因：
- 依赖缺失 → 运行 `./build.sh feed` 重装
- 配置不匹配 → 运行 `make defconfig` 修复
- 磁盘空间不足 → 至少需要 15GB 可用空间

### Q: 如何只编译某个模块？
A: `make package/luci-app-arx-dashboard/compile V=s`

### Q: 如何导出当前配置？
A: `./build.sh diffconfig` 会将精简差异保存到 `config/rax3000m.diffconfig.min`。`config/rax3000m.config` 仍是仓库中的完整预置配置（CI 使用）；需要固化改动时请把差异合并进该文件或据此手工更新。

### Q: WSL2 下编译可以吗？
A: 可以，但建议设置 `.gitconfig` 并确保有足够磁盘空间。

### Q: GitHub Actions 编译要多久？
A: 首次编译约 45-90 分钟（需要下载源码包），后续有缓存约 20-40 分钟。

### Q: 如何修改 .config 后重新触发编译？
A: 修改 `config/rax3000m.config` 后 push 即可。CI 会根据配置文件 hash 自动失效缓存。

### Q: Actions 报错怎么办？
A: 下载 `build-log-xxx` Artifact 查看 `build.log` 尾部错误信息，本地修复后重新 push。

## 许可证

Apache-2.0 License
