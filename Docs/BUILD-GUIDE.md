# 编译教程（本地编译 / GitHub 工作流编译）

本仓库有两条编译路径，**共用同一套流程脚本**`Scripts/build-core.sh`，因此在同一源码与分支下，两边产出的配置与固件行为一致：

| 路径 | 适用场景 | 入口 |
| ---- | -------- | ---- |
| GitHub 工作流（云编译） | 日常自动/手动出固件，不用自己的机器 | `.github/workflows/*.yml` |
| 本地 Ubuntu 编译 | 调试试错、临时改配置、不想占用 Actions 额度 | `Scripts/local-build.sh` |

---

## 目录与文件职责

| 路径 | 作用 |
| ---- | ---- |
| `.github/workflows/WRT-CORE.yml` | 云编译核心流程，被其它工作流调用，内部只调用 `Scripts/build-core.sh` |
| `.github/workflows/WRT-TEST.yml` | 通用云编译入口（可选平台/源码/分支，默认只输出配置） |
| `.github/workflows/AIR-TCBOOT.yml` | 贝尔系列 tcboot 固件定时编译（每天 3 点 UTC / 北京 11 点），上游无更新自动跳过 |
| `.github/workflows/Auto-Clean.yml` | AIR-TCBOOT 完成后清理旧 Release 与旧 Workflow 记录（保留各设备线最新版本，当前保留 2 个） |
| `.github/workflows/AIR-ONU.yml` | ONU（uboot）固件编译，由 Auto-Clean 完成后自动触发，也可手动 |
| `.github/workflows/Cache-Clean.yml` | 每周清理 Actions 编译缓存 |
| `Scripts/build-core.sh` | 流程主体：feeds → 插件 → 配置 → 下载 → 编译（云/本地共用） |
| `Scripts/local-build.sh` | 本地编译入口：环境检查、拉源码、调用 build-core |
| `Scripts/Packages.sh` | 自定义插件仓库克隆与版本更新 |
| `Scripts/Settings.sh` | 固件默认参数（主题/主机名/IP/WiFi/密码）注入 |
| `Scripts/Handles.sh` | 插件安装后的收尾处理（由 `build-core.sh` 调用） |
| `Config/<平台>.txt` | 各平台 `.config` 片段（含 `CONFIG_TARGET_*`） |
| `Config/GENERAL.txt` | 全平台通用片段，非 TEST 配置都会自动拼接在平台片段之后 |
| `Config/PRIVATE.txt` | 私有配置片段（可选），最后追加到 `.config`，可加入 `.gitignore` 不公开 |
| `Scripts/PRIVATE.sh` | 私有扩展脚本（可选），在插件克隆完成后执行 |

---

## 一、GitHub 工作流编译

### 1. 自动流程（无需操作）

```
每天 11:00（北京时间）
  AIR-TCBOOT  → 检查上游 bingoguo93/immortalwrt@6.18 是否有新提交
               ├─ 无更新：直接结束
               └─ 有更新：编译 AIROHA-TCBOOT → 记录上游 SHA
  Auto-Clean  → 删除旧 Release / 旧 Workflow（保留各设备线最新版本，当前 2 个）
  AIR-ONU     → 自动编译 AIROHA-ONU（uboot 版）
```

固件与配置文件都会发布到仓库 **Releases** 页面。

### 2. 手动触发

1. 打开仓库 → **Actions**
2. 左侧选择工作流：
   - 出正式固件：`AIR-TCBOOT` 或 `AIR-ONU`
   - 临时试配置：`WRT-TEST`
3. 右侧 **Run workflow**，填参数后运行

### 3. 参数说明（AIR-ONU / AIR-TCBOOT）

| 参数 | 说明 |
| ---- | ---- |
| `PACKAGE` | 临时追加到 `.config` 的插件配置，多个用换行分隔，例如 `CONFIG_PACKAGE_luci-app-mosdns=y` |
| `TEST` | 勾选后**只输出配置文件**，不编译固件，用于快速验证配置是否会报错 |

> 主题 / 主机名 / WiFi / IP 等默认值写在对应 yml 的 `with:` 段（`WRT_THEME`、`WRT_NAME`、`WRT_SSID`、`WRT_WORD`、`WRT_IP`），改完提交即可。

### 4. WRT-TEST 参数

| 参数 | 说明 |
| ---- | ---- |
| `CONFIG` | 配置名（对应 `Config/<名字>.txt`） |
| `SOURCE` / `BRANCH` | 上游源码与分支 |
| `PACKAGE` | 追加插件配置 |
| `TEST` | 默认 `true`（只出配置），取消勾选才会真正编译 |

### 5. 云编译常见问题

- **没出固件**：先看 Release 是否有新 tag；`AIR-TCBOOT` 定时任务在上游无更新时会主动跳过，属正常。
- **配置验证**：不确定配置是否可用时，手动跑一次并勾选 `TEST`，几十分钟内即可在 Release 里拿到 `Config-*.txt`（本仓库只发 Release，不产生 Actions Artifact）。
- **缓存问题**：编译环境异常时先手动运行 `Cache-Clean`（`gh cache delete --all`）再重跑。
- **失败重跑**：Actions 页面进入失败 run → **Re-run failed jobs**，无需改动代码。

---

## 二、本地 Ubuntu 编译

### 1. 环境要求

| 项目 | 建议 |
| ---- | ---- |
| 系统 | Ubuntu 22.04 / 24.04（同为 Debian 系的其它发行版需自行装依赖） |
| 磁盘 | 完整编译 ≥ 25 GB，只生成配置（`--test`）≥ 6 GB |
| 内存 | ≥ 8 GB（4 GB 机器请把并行降到 `-j 2`） |
| 网络 | 需要能访问 GitHub（国内可加 `--proxy`） |

编译依赖（脚本会自动检测，缺失时给出安装命令，或加 `--install-deps` 自动安装）：

```bash
sudo apt update
sudo apt install -y build-essential clang flex bison g++ gawk gcc-multilib g++-multilib \
  gettext git libncurses-dev libssl-dev python3-setuptools python3-dev rsync swig \
  unzip zlib1g-dev file wget curl libelf-dev jq
```

### 2. 快速开始

```bash
# 0) 进入本仓库目录（脚本要在仓库内执行）
cd OpenWRT-CI-XG-040G-MD

# 1) 先验证环境：拉源码 + 安装插件 + 生成配置，不出固件（约 5~15 分钟）
bash Scripts/local-build.sh --test

# 2) 确认无误后完整编译（首次约 1~3 小时，取决于机器）
bash Scripts/local-build.sh

# 3) 只编译某个平台
bash Scripts/local-build.sh -c AIROHA-TCBOOT
bash Scripts/local-build.sh -c X86 -j 4
```

> **国内网络**：直连 GitHub 常出现 `gnutls_handshake() failed` 或克隆超时，加加速前缀即可（实测可用：`https://ghfast.top/`、`https://gh-proxy.com/`、`https://gh.llkk.cc/`）：
>
> ```bash
> bash Scripts/local-build.sh --test --proxy https://ghfast.top/
> ```

远程 Ubuntu（例如通过 SSH 登录服务器）时，把仓库同步上去再执行同样命令即可，脚本本身不依赖任何 GUI。

### 3. 参数说明

| 参数 | 说明 |
| ---- | ---- |
| `-c, --config NAME` | 配置名，对应 `Config/NAME.txt`，默认 `AIROHA-ONU` |
| `-d, --dir DIR` | 源码目录，默认 `~/openwrt-build/<小写配置名>` |
| `-r, --repo REPO` | 上游源码，默认 `pbs05/ponwrt` |
| `-b, --branch NAME` | 上游分支，默认 `master` |
| `-j, --jobs N` | 并行任务数，默认按 CPU 与内存自动计算（内存小时会自动降低），可手动指定 |
| `-p, --package TEXT` | 追加 `.config` 内容，等价云编译的 `PACKAGE` |
| `-t, --test` | 只生成配置，不编译固件（仍会更新 feeds、克隆插件源码，需要网络） |
| `-m, --menuconfig` | 生成配置后进入 `make menuconfig` 手动微调 |
| `--install-deps` | 自动安装缺失依赖（需要 sudo） |
| `--skip-deps` | 跳过依赖检查，`--test` 只生成配置时可跳过 |
| `--force-clone` | 删除已有源码目录重新拉取 |
| `--proxy URL` | GitHub 加速前缀（国内网络必备），例如 `--proxy https://ghfast.top/`；本次运行内所有 github 克隆都走加速，不改动 git 全局配置 |

固件参数与构建开关都可用环境变量覆盖（`build-core.sh` 直接读这些变量）：

| 环境变量 | 默认值 | 说明 |
| ---- | ------ | ---- |
| `WRT_THEME` | `argon` | LuCI 主题（云编译 `WRT-TEST` 默认 `aurora`） |
| `WRT_NAME` / `WRT_SSID` / `WRT_WORD` / `WRT_PW` | `OWRT` / `OWRT` / `12345678` / `无` | 主机名、WiFi 名、WiFi 密码、登录密码 |
| `WRT_IP` | `192.168.100.1` | 管理地址 |
| `WRT_SKIP_CLEAN` | `false` | 设为 `true` 跳过 `make clean`，复用已有产物、加快二次编译 |
| `WRT_JOBS` | 按 CPU / 内存自动计算 | 并行任务数 |
| `WRT_WORKSPACE` / `WRT_DIR` | 脚本所在仓库 / `<workspace>/wrt` | 仓库根目录与源码目录 |

```bash
WRT_THEME=aurora WRT_SSID=MyWiFi WRT_WORD=12345678 WRT_IP=192.168.10.1 \
  WRT_SKIP_CLEAN=true bash Scripts/local-build.sh -c AIROHA-ONU
```

需要单独排障时，可以直接调用核心脚本的分步命令：

```bash
bash Scripts/build-core.sh feeds      # 只更新 feeds
bash Scripts/build-core.sh packages   # 只克隆/更新插件
bash Scripts/build-core.sh config     # 只重新生成 .config
bash Scripts/build-core.sh compile    # 只编译固件
```

### 4. 产物位置

| 内容 | 路径 |
| ---- | ---- |
| 生成的配置 | `<源码目录>/.config` |
| 固件 | `<源码目录>/bin/targets/` |
| 编译日志 | 终端输出，建议 `bash Scripts/local-build.sh 2>&1 \| tee build.log` |

### 5. 与云编译的差异

- **保留国内下载源**：云编译会删除 `scripts/projectsmirrors.json` 里的国内源（GitHub 机器在国外），本地编译**不删**，下载更快。
- **不启用 Actions 缓存**：cloud 上的 ccache/toolchain 缓存本地没有，首次全量编译更慢属正常。
- **源码更新**：本地默认复用已存在的源码目录；需要换版本时用 `--force-clone`。
- **流程一致性**：feeds、插件、配置三个阶段与云编译完全同一份脚本，云上能过的配置本地同样能过。

### 6. 本地编译常见问题

| 现象 | 处理 |
| ---- | ---- |
| `磁盘空间不足` | 清理空间，或用 `-d` 指向大分区 |
| 编译中途被 OOM kill | 降低并行 `-j 2`，或加 swap |
| `git clone` 极慢/超时 | 加 `--proxy https://ghfast.top/`，或提前用代理拉好源码目录再跑 |
| `feeds update` 卡住 | 重跑一次即可（feeds 支持断点续传） |
| 想改完个别插件再编 | `-m` 进 menuconfig，或改 `Config/*.txt` 后重跑 |
| 编译失败想复现细节 | `cd <源码目录> && make -j1 V=s` 单线程重跑看报错 |

---

## 三、改完东西如何生效

| 改动 | 生效方式 |
| ---- | -------- |
| `Config/*.txt`（插件开关） | 云编译直接重跑工作流；本地重跑 `local-build.sh`（复用源码目录即可） |
| `Scripts/Packages.sh`（插件增删/版本） | 同上；本地若插件目录已存在，需要 `--force-clone` 或手动删除源码目录后重跑 |
| `Scripts/Settings.sh`（默认主题/IP/WiFi） | 同上 |
| `Scripts/build-core.sh` / `local-build.sh` | 云编译与本地编译同时生效 |
| `.github/workflows/*.yml` | 仅影响云编译 |

---

## 四、名词对照

| 名称 | 对应固件 |
| ---- | -------- |
| `AIROHA-TCBOOT` | 贝尔 XG-040G/140G 系列 tcboot 版（nokia 4 个机型） |
| `AIROHA-ONU` | 贝尔 XG-040G/140G 系列 uboot（ONU）版，共 9 个机型 |
| `AIROHA-MAIN` | 贝尔主固件最小片段（仅 target 与专属包），通用组件在 `Config/GENERAL.txt`，目前只在 `WRT-TEST` 的可选配置里出现 |
| `GENERAL` | 全平台通用配置片段，自动拼接在平台片段后 |
