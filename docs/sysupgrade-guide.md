# RAX3000M（cmcc_rax3000m）刷机与升级指南

本文涵盖两种场景：

1. **首次刷机**：设备仍在运行原厂中移固件，需要刷入 OpenWrt。
2. **系统内升级（sysupgrade）**：设备已运行 OpenWrt，日常升级到新版本。

---

## 1. 硬件变体确认（必读）

RAX3000M 存在两种存储版本，**混刷会变砖**，刷机前必须确认：

| 判断依据（机身标签） | 存储类型 | 对应固件 |
|----------------------|----------|----------|
| 标签无「EC」字样 | **NAND 版**（主流） | `*squashfs-sysupgrade.itb` |
| 标签含「EC」字样 | **eMMC 算力版** | `emmc-*` 系列 |

本文以 **NAND 版**为主。eMMC 版流程类似，但所有文件名均需选 `emmc-*` 对应版本。

---

## 2. 首次刷机（原厂固件 → OpenWrt）

### 2.1 确认你的 DDR 版本

NAND 版还分 DDR3 / DDR4，救砖包需要匹配。查看方式：

- 机身标签上通常有内存规格标注
- 或进入原厂后台 → 系统信息查看

### 2.2 方法一：原厂 Web 界面直刷（最简单）

部分中移原厂固件允许直接上传第三方固件：

1. 连接路由器，浏览器打开 `192.168.10.1`（原厂默认地址）
2. 进入「系统升级」或「固件升级」页面
3. 上传 `openwrt-mediatek-filogic-cmcc_rax3000m-squashfs-sysupgrade.itb`
4. 等待重启完成

> 注意：部分中移固件版本会校验签名，拒绝第三方固件。若上传后提示失败，需改用方法二。

### 2.3 方法二：U-Boot + TFTP 刷入（通用方法）

适用于原厂固件锁签名、或设备变砖需要救砖的情况。

**准备工作：**

- 电脑安装 TFTP 服务器（Windows 推荐 [Tftpd64](https://pjo2.github.io/tftpd64/)）
- 电脑有线连接路由器 LAN 口
- 电脑 IP 设为 `192.168.1.254`，子网掩码 `255.255.255.0`

**所需文件（从 Release 下载，注意 DDR3/DDR4 匹配）：**

| 文件 | 用途 |
|------|------|
| `mt7981-ram-ddr3-bl2.bin` 或 `mt7981-ram-ddr4-bl2.bin` | 内存初始化 BL2 |
| `openwrt-...-nand-ddr3-bl31-uboot.fip` 或 `nand-ddr4-*` | U-Boot FIP |
| `openwrt-...-squashfs-sysupgrade.itb` | OpenWrt 固件 |

**刷入步骤：**

1. 将上述文件放入 TFTP 服务器根目录，重命名为：
   - `bl2.bin`
   - `fip.bin`
   - `firmware.itb`

2. 路由器断电，按住 Reset 键不放，插电，等待约 5 秒后松开（进入 U-Boot 恢复模式）

3. U-Boot 会自动通过 TFTP 从 `192.168.1.254` 拉取文件并刷入

4. 刷入完成后自动重启，等待 2-3 分钟

5. 浏览器访问 `192.168.1.1`，默认无密码登录 LuCI

> 若 U-Boot 未自动拉取，可通过串口连接手动执行命令。串口参数：115200 8N1。

### 2.4 首次刷机后

- 默认 IP：`192.168.1.1`
- 默认用户名：`root`，无密码
- 建议立即设置密码：LuCI → 系统 → 管理权 → 修改密码

---

## 3. 适用场景与前提（系统内升级）

| 条件 | 说明 |
|------|------|
| 当前状态 | 设备能正常启动并进入 OpenWrt（LuCI 或 SSH 可用）。 |
| 目标设备 | **中移 RAX3000M**，OpenWrt 目标 **`mediatek/filogic`**，设备名 **`cmcc_rax3000m`**。 |
| 升级包类型 | 使用文件名含 **`sysupgrade`** 的 **`.itb`**（FIT 镜像），在运行系统中执行 **`sysupgrade`**。 |

若你此前用 **U-Boot / TFTP** 写过镜像，只要现在 OpenWrt 工作正常，**后续版本升级通常仍在系统内用 `sysupgrade` 即可**，无需每次进 U-Boot。

---

## 4. NAND 与 eMMC 不可混刷

本机型存在不同存储版本，**错误变体会直接导致无法启动或变砖**。

| 判断依据（机身标签） | 存储类型 | 升级时注意 |
|----------------------|----------|------------|
| **「CH  CMIIT ID」**，EC 位置为空 | 多为 **NAND** 版 | 日常升级只用 **`sysupgrade`** 的 **`.itb`**；**不要**刷 `emmc-*` 裸写包。 |
| **「CH EC CMIIT ID」**（含 EC） | **eMMC 算力版** | 与 NAND 分区布局不同，**固件与救砖包均不能与 NAND 机混用**。 |

上游同一 `cmcc_rax3000m` 目标会产出多种文件名（含 `nand-ddr3`、`nand-ddr4`、`emmc` 等）。**在系统内做「日常升级」时，只使用 `sysupgrade` 目录下、带 `sysupgrade` 字样的 `.itb`**；`nand-ddr*`、`emmc-*` 的 **preloader / fip** 属于 **U-Boot 层裸写**，不是常规在线升级包。

CI 或本地脚本 `scripts/split-firmware-artifacts.sh` 会将产物分到：

- **`sysupgrade/`**：日常升级、recovery、manifest 等；
- **`nand-boot/`**、**`emmc-boot/`**：对应裸刷用，勿当普通 sysupgrade 误选；
- **`misc/`**：未归入上列的上游文件，**勿当作日常 sysupgrade**。

---

## 5. 应使用的文件（系统内升级）

从编译输出或 Release / Artifacts 的 **`sysupgrade/`** 中取：

- 推荐：`openwrt-*-mediatek-filogic-cmcc_rax3000m-squashfs-sysupgrade.itb`（具体前缀版本号以实际文件名为准）。

**不要使用**：

- `*-initramfs-recovery.itb`：用于串口/TFTP 等恢复场景，**不是**常规「保留配置升级」用的包（除非官方救砖流程明确要求）。
- 仅含 `nand-ddr*` / `emmc` 且为 **preloader / fip** 的文件：属于裸写，在已正常运行的 OpenWrt 里一般**不应**当 sysupgrade 包刷入。

---

## 6. 升级前准备

### 4.1 校验文件完整性（推荐）

在电脑上下载固件后，与随包提供的 **`sha256sums`**（或 Release 上公布的 SHA256）对比，避免下载或拷贝损坏。Artifact / zip 解压后请先进入 **`sysupgrade/`** 子目录再校验（该目录内的 `sha256sums` 仅覆盖本目录文件）。

**Linux / macOS：**

```bash
cd sysupgrade
sha256sum -c sha256sums
# 或
sha256sum openwrt-xxx-sysupgrade.itb
```

**Windows（PowerShell）：**

```powershell
Get-FileHash -Algorithm SHA256 .\openwrt-xxx-sysupgrade.itb
```

### 4.2 备份（强烈建议）

- **LuCI**：「系统 → 备份/升级 → 生成备份」下载配置归档。
- 或 SSH：`sysupgrade -b /tmp/backup-$(date +%Y%m%d).tar.gz`（视系统是否支持该参数而定；若无则用 LuCI 备份）。

重要环境变量、拨号账号、自定义防火墙等务必单独留档。

### 4.3 确认路由器侧信息（可选但有用）

用 SSH 登录（默认 `root`，地址多为 `192.168.1.1`，以你实际为准）：

```sh
ubus call system board
cat /etc/openwrt_release
```

关注 **`board_name` / `model`** 是否与 **CMCC RAX3000M / cmcc,rax3000m** 一类描述一致。若此处显示完全另一款机型，**先不要升级**，核对是否下错固件。

---

## 5. 将固件传到路由器

固件需放在路由器可写位置，常用 **`/tmp`**（内存盘，重启即清空；空间一般足够放一个 `.itb`）。

**从电脑拷贝（SCP 示例）：**

```bash
scp openwrt-xxx-sysupgrade.itb root@192.168.1.1:/tmp/
```

**路由器自行下载（示例）：**

```sh
cd /tmp
wget -O firmware.itb "https://你的直链或内网地址/固件.itb"
```

若 `/tmp` 空间不足，先删除大文件或换用外接存储路径（若你的固件支持挂载 U 盘）。

---

## 6. 先测试兼容性（强烈建议）

**注意**：`sysupgrade/` 中可能同时存在 `*recovery*.itb` 与 `*squashfs*sysupgrade*.itb`。下面命令假设你已将**日常升级包**（文件名含 `sysupgrade`）放到 `/tmp/firmware.itb`；**不要**对 recovery 镜像做常规在线升级。

在**不写 Flash** 的前提下，让系统检查镜像是否可被接受：

```sh
sysupgrade -T /tmp/firmware.itb
```

- **退出码为 0 且无错误提示**：通常表示可进行下一步升级（仍请确认文件未损坏、机型与变体正确）。
- **报错或拒绝**：不要立刻加 `-F` 强刷。核对机型、NAND/eMMC、`sysupgrade` 包是否选对；仍失败时查阅救砖/recovery 说明。

---

## 7. 执行升级（命令行）

### 7.1 保留现有配置（常见）

```sh
sysupgrade /tmp/firmware.itb
```

或显式详细日志：

```sh
sysupgrade -v /tmp/firmware.itb
```

### 7.2 不保留配置（相当于干净刷，避免旧配置冲突）

```sh
sysupgrade -n /tmp/firmware.itb
```

大版本跨越、或从第三方固件换到本构建时，若出现异常，可尝试 **`-n`** 干净刷后再手工恢复必要配置。

### 7.3 常用参数说明

| 参数 | 含义 |
|------|------|
| `-T` / `--test` | 仅测试镜像与兼容性，**不刷写**。 |
| `-n` | 不保留配置。 |
| `-v` | 更详细输出。 |
| `-F` / `--force` | **强制**忽略部分检查。**仅在明确知道风险时使用**，否则可能变砖。 |

执行成功后，设备会**自动重启**。**整个过程请勿断电**，等待数分钟直至 Web/SSH 恢复。

---

## 8. 使用 LuCI 网页升级

1. 浏览器打开路由器管理地址（如 `http://192.168.1.1`）。
2. 进入 **「系统 → 备份/升级」**（不同主题文案可能略有差异）。
3. 在 **「刷写固件」** 区域选择本地的 **`*sysupgrade*.itb`**。
4. 勾选是否 **保留配置**（与命令行是否加 `-n` 对应）。
5. 确认后开始刷写，等待重启完成。

网页与命令行底层调用的是同一套 `sysupgrade` 逻辑；**同样建议先上传后用 SSH 做一次 `sysupgrade -T`**（需先把文件放到 `/tmp`），若仅 LuCI 无单独「仅检测」按钮，则以备份充分、选对文件为优先。

---

## 9. 升级后检查

```sh
cat /etc/openwrt_release
ubus call system board
uname -a
```

确认版本与内核符合预期。若使用本仓库 LuCI 主题与插件，逐项打开 **Dashboard、Network Manager** 等确认无报错。

---

## 10. 何时不要依赖「普通 sysupgrade」

出现以下情况时，请先查官方/OpenWrt 设备页与本仓库 **编译产物** 说明，必要时使用 **recovery `.itb`、TFTP、串口** 等流程，而不是强行 `sysupgrade`：

- `sysupgrade -T` 持续失败，且已确认文件与机型无误；
- 曾刷入错误变体（NAND/eMMC 混用）或分区被异常修改；
- 设备反复启动失败、只能进 U-Boot。

---

## 11. 常见问题（FAQ）

**Q：从别人编译的 OpenWrt 换到本仓库固件，可以直接 sysupgrade 吗？**  
A：若硬件同为 RAX3000M 且变体一致，且当前系统分区正常，一般可以。务必先 **`sysupgrade -T`**；跨版本或大改时若有问题，可尝试 **`-n`** 干净刷。

**Q：`.itb` 和以前的 `.bin` 有什么区别？**  
A：上游对本机型的**系统升级镜像为 FIT 格式的 `.itb`**。请使用带 **`sysupgrade`** 的 **`.itb`**，不要凭旧教程硬套 `squashfs-sysupgrade.bin` 文件名。

**Q：升级中途断电会怎样？**  
A：可能导致变砖或需救砖。务必保证供电稳定，笔记本建议接电源。

**Q：能否用 `sysupgrade -F` 强行刷？**  
A：仅在完全理解后果时使用；多数情况下应先解决「为何不兼容」而不是强刷。

---

## 12. 相关仓库说明

- 编译产物目录与命名：见主文档 **[README.md](README.md)** 中的「编译产物」一节。
- 产物按用途分目录：`scripts/split-firmware-artifacts.sh`（含 `sysupgrade/`、`nand-boot/`、`emmc-boot/`、`misc/`）。

---

*文档对应 OpenWrt 目标 `CONFIG_TARGET_mediatek_filogic_DEVICE_cmcc_rax3000m`；若上游变更镜像命名，请以 `bin/targets/mediatek/filogic/` 下实际文件名为准。*
