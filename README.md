# OpenWRT-CI — 贝尔 XG-040G / XG-140G 系列 ImmortalWrt 固件

贝尔 040G/140G 系列 ImmortalWrt 固件（AIR-TCBOOT 线使用 6.18 内核）  
刷机前必须备份所有原厂分区，特别是ri和bosa分区

详细说明  
https://www.right.com.cn/forum/thread-8453612-1-1.html

支持设备：TCBOOT 四个固件通用，设备名称只是区分不同功能；ONU（uboot）线共 9 个机型。

| 设备 | WAN 定义 | USB 支持 | UBOOT |
| ---- | -------- | -------- | ------ |
| XG-040G-MD | pon0 | USB2 USB3 | tcboot |
| XG-140G-MD | pon0 | USB2 USB3 | tcboot |
| XG-040G-TF | pon0 | 硬件无 USB 口（固件仍带 USB 驱动） | tcboot |
| XG-140G-TF | pon0 | 硬件无 USB 口（固件仍带 USB 驱动） | tcboot |

ONU（uboot）线机型：fiberhome hg5382a / hg5585f-ct / hg5585f-cu、gemtek xg2010g、nokia xg-040g-md-ubi / xg-040g-tf-ubi、unionman ung00a、znxt zn504xg-d / zn515xg-d，完整列表见 [Config/AIROHA-ONU.txt](Config/AIROHA-ONU.txt)。

## 恢复MAC地址说明
刷机前必须备份所有原厂分区，特别是ri和bosa分区，参考详细说明刷回备份


## 固件简要说明

固件每天北京时间 11:00 自动检查上游更新并编译（上游无新提交时自动跳过）。

固件信息里的时间为编译开始的时间，方便核对上游源码提交时间。

贝尔040系列，140系列。

## 目录简要说明

.github/workflows——自定义CI配置

Scripts——自定义脚本（编译核心、插件克隆、参数注入、本地编译入口）

Config——自定义配置（各平台 .config 片段 + 通用片段）

Docs——编译教程

私有定制（可选，不随仓库公开）：`Config/PRIVATE.txt` 会追加到最终 `.config`；`Scripts/PRIVATE.sh` 会在插件克隆完成后执行。

## 编译教程

- 本地编译（Ubuntu）与 GitHub 工作流编译完整说明：[Docs/本地编译教程和工作流教程.md](Docs/本地编译教程和工作流教程.md)
- 本地编译快速开始：先 `bash Scripts/local-build.sh --test` 验证配置，再 `bash Scripts/local-build.sh` 完整编译

