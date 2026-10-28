#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

# 云编译（.github/workflows/WRT-CORE.yml）与本地编译（Scripts/local-build.sh）共用的核心流程
# 用法: bash Scripts/build-core.sh <feeds|packages|config|download|compile|all>
#
# 可用环境变量:
#   WRT_WORKSPACE  仓库根目录（默认脚本上一级）
#   WRT_DIR        源码目录（默认 $WRT_WORKSPACE/wrt）
#   WRT_CONFIG     配置文件名，不带 .txt（默认 AIROHA-ONU）
#   WRT_THEME WRT_NAME WRT_SSID WRT_WORD WRT_IP WRT_PW WRT_PACKAGE
#   WRT_TEST       true 时只生成配置，不下载不编译
#   WRT_JOBS       并行任务数（默认按 CPU 与内存自动计算）
#   WRT_SKIP_CLEAN 默认 true：跳过 make clean，走增量编译；设 false 彻底干净重编

set -euo pipefail

STEP="${1:-all}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- 工作区与源码目录 ----
: "${WRT_WORKSPACE:=$(cd "$SCRIPT_DIR/.." && pwd)}"
: "${WRT_DIR:=$WRT_WORKSPACE/wrt}"
: "${GITHUB_WORKSPACE:=$WRT_WORKSPACE}"

# 并行度：按 CPU 与内存共同决定（部分包编译占用内存较多，纯按 nproc 容易 OOM）
auto_jobs() {
	local cpus mem_gb by_mem
	cpus=$(nproc 2>/dev/null || echo 4)
	mem_gb=$(awk '/MemTotal/ {printf "%d", $2/1048576}' /proc/meminfo 2>/dev/null || echo 4)
	[ "$mem_gb" -lt 1 ] && mem_gb=1

	by_mem=$(( mem_gb * 2 / 3 ))
	[ "$by_mem" -lt 1 ] && by_mem=1

	if [ "$cpus" -lt "$by_mem" ]; then echo "$cpus"; else echo "$by_mem"; fi
}
: "${WRT_JOBS:=$(auto_jobs)}"

# 物理内存（GB）。rust host 包内部的 LLVM 并行度要按它限流，见 do_compile。
WRT_MEM_GB=$(awk '/MemTotal/ {printf "%d", $2/1048576}' /proc/meminfo 2>/dev/null || echo 4)
[ "$WRT_MEM_GB" -lt 1 ] && WRT_MEM_GB=1

# ---- 编译参数默认值（本地编译不传参也能跑）----
: "${WRT_CONFIG:=AIROHA-ONU}"
: "${WRT_THEME:=argon}"
: "${WRT_NAME:=OWRT}"
: "${WRT_SSID:=OWRT}"
: "${WRT_WORD:=12345678}"
: "${WRT_IP:=192.168.100.1}"
: "${WRT_PW:=无}"
: "${WRT_PACKAGE:=}"
: "${WRT_TEST:=false}"
# 默认跳过 make clean（增量编译）：OpenWrt 的 make clean 会连
# staging_dir/hostpkg/stamp/ 一起清掉，导致 rust host 包（内部还要构建一套
# LLVM，耗时 1.5~2 小时）每次从头重编。跳过清理后复用已有产物，
# 日常改配置 / 调插件只需 5~15 分钟。
# 发版前要彻底干净重编时，显式设 WRT_SKIP_CLEAN=false（或 local-build.sh 加 --clean）。
: "${WRT_SKIP_CLEAN:=true}"
: "${WRT_MARK:=local}"
: "${WRT_DATE:=$(TZ=UTC-8 date +'%y.%m.%d-%H.%M.%S')}"

CONFIG_FILE="$WRT_WORKSPACE/Config/$WRT_CONFIG.txt"

# 目标平台（Scripts/Settings.sh 依赖）
if [ -z "${WRT_TARGET:-}" ]; then
	WRT_TARGET="$(grep -m 1 -oP '^CONFIG_TARGET_\K[\w]+(?==y)' "$CONFIG_FILE" 2>/dev/null || true)"
	WRT_TARGET="${WRT_TARGET:-none}"
fi

# Scripts/*.sh 依赖 GITHUB_* 变量，本地编译时补齐（临时文件在脚本退出时清理）
GITHUB_ENV_TMP=""
if [ -z "${GITHUB_ENV:-}" ] || ! ( : >> "$GITHUB_ENV" ) 2>/dev/null; then
	GITHUB_ENV_TMP="$(mktemp -t wrt-build-env.XXXXXX)"
	GITHUB_ENV="$GITHUB_ENV_TMP"
fi

# Scripts/Handles.sh 等脚本使用固定的 $GITHUB_WORKSPACE/wrt 路径，
# 本地编译指定了其它源码目录时用符号链接补齐（脚本退出时自动清理）
WRT_LINK="$WRT_WORKSPACE/wrt"
LINK_CREATED="false"
if [ "$WRT_DIR" != "$WRT_LINK" ] && [ ! -e "$WRT_LINK" ] && [ ! -L "$WRT_LINK" ]; then
	if ln -s "$WRT_DIR" "$WRT_LINK" 2>/dev/null; then
		LINK_CREATED="true"
	fi
fi

cleanup() {
	if [ "$LINK_CREATED" = "true" ] && [ -L "$WRT_LINK" ]; then
		rm -f "$WRT_LINK"
	fi
	if [ -n "$GITHUB_ENV_TMP" ]; then
		rm -f "$GITHUB_ENV_TMP"
	fi
	return 0
}
trap cleanup EXIT

export GITHUB_WORKSPACE GITHUB_ENV
export WRT_WORKSPACE WRT_DIR WRT_TARGET WRT_CONFIG WRT_THEME WRT_NAME WRT_SSID
export WRT_WORD WRT_IP WRT_PW WRT_PACKAGE WRT_TEST WRT_MARK WRT_DATE WRT_JOBS

need_source() {
	[ -d "$WRT_DIR" ] || { echo "错误: 源码目录不存在: $WRT_DIR"; exit 1; }
}

check_config() {
	if [ ! -f "$CONFIG_FILE" ]; then
		echo "错误: 配置文件不存在: $CONFIG_FILE"
		echo "可用配置:"
		for FILE in "$WRT_WORKSPACE"/Config/*.txt; do
			echo "  - $(basename "$FILE" .txt)"
		done
		exit 1
	fi
}

do_feeds() {
	need_source
	cd "$WRT_DIR"
	echo "==> 更新 feeds"
	./scripts/feeds update -a
	./scripts/feeds install -a
}

do_packages() {
	need_source
	cd "$WRT_DIR/package"
	echo "==> 安装自定义插件"
	bash "$WRT_WORKSPACE/Scripts/Packages.sh"
	bash "$WRT_WORKSPACE/Scripts/Handles.sh"
}

do_config() {
	need_source
	check_config
	cd "$WRT_DIR"
	echo "==> 生成 .config（$WRT_CONFIG）"

	# 清空旧配置：复用源码目录重跑时避免与上一次的配置叠加
	rm -f .config .config.old

	if [ "${WRT_CONFIG^^}" = "TEST" ]; then
		cat "$CONFIG_FILE" >> .config
	else
		cat "$CONFIG_FILE" "$WRT_WORKSPACE/Config/GENERAL.txt" >> .config
	fi

	bash "$WRT_WORKSPACE/Scripts/Settings.sh"

	make defconfig

	if [ "$WRT_SKIP_CLEAN" = "true" ]; then
		echo "==> 已跳过 make clean，复用已有构建产物（增量编译）"
	else
		echo "==> 执行 make clean（注意：会清掉 rust 标记，rust host 包将重编 1.5~2 小时）"
		make clean
	fi
}

do_download() {
	need_source
	if [ "$WRT_TEST" = "true" ]; then
		echo "==> WRT_TEST=true，跳过下载"
		return 0
	fi

	cd "$WRT_DIR"
	echo "==> 下载软件包源码"
	make download -j"$WRT_JOBS" || make download -j1 V=s
}

do_compile() {
	need_source
	if [ "$WRT_TEST" = "true" ]; then
		echo "==> WRT_TEST=true，跳过编译"
		return 0
	fi

	cd "$WRT_DIR"

	# rust 的 host 包内部还会再开一轮 LLVM 的 ninja 构建，它才是真正的资源大户：
	# LLVM 里 AMDGPU 的几张 .inc 和几个 CXX 大文件，单个就能吃掉 2~3 GB 内存，
	# 并行编译时峰值叠加，小内存机器会被内核直接 SIGKILL——日志里的表现是
	# "FAILED: [code=137]" 紧跟一行 "Killed"（137 = 128 + 9），然后 rust 与
	# 整个编译一起失败。所以这里做两件事：
	#   1) 外层用 -j1，避免和其它软件包抢资源；
	#   2) 按物理内存限制它内部 LLVM 的并行度（8 GB 机器只给 2 路）。
	# 成功后 staging_dir/hostpkg/stamp/.rust_installed 落盘，主构建不会再碰它，
	# 这一步不会重复编译；已编过时会直接秒过。
	local rust_pkg="package/feeds/packages/rust"
	if [ -d "$rust_pkg" ]; then
		# 实测：AMDGPU 的 tblgen（AMDGPUGenGlobalISel.inc / AMDGPUGenAsmMatcher.inc）
		# 是整条链上的内存黑洞，单个 llvm-tblgen 进程峰值就能吃掉 4~6 GB。
		# 8 GB 机器即便只开 2 路也会在 [1750/3898] 附近被 SIGKILL（可用内存看着
		# 还有 6 GB，但单进程瞬时峰值就超了）。所以 12 GB 以下一律单路。
		local rust_jobs=1
		[ "$WRT_MEM_GB" -ge 12 ] && rust_jobs=2
		[ "$WRT_MEM_GB" -ge 16 ] && rust_jobs=4
		[ "$WRT_MEM_GB" -ge 32 ] && rust_jobs=6
		echo "==> 预编译 rust host 包（外层 -j1，内部 LLVM 并行 $rust_jobs，规避 OOM）"
		echo "    日志：$WRT_DIR/rust-host-build.log"
		if ! CMAKE_BUILD_PARALLEL_LEVEL="$rust_jobs" NUM_JOBS="$rust_jobs" \
			make "$rust_pkg/host/compile" -j1 V=s >"$WRT_DIR/rust-host-build.log" 2>&1; then
			echo "!! rust host 包编译失败，日志尾部："
			tail -40 "$WRT_DIR/rust-host-build.log"
			exit 1
		fi
		echo "==> rust host 包就绪"
	fi

	echo "==> 开始编译（并行 $WRT_JOBS）"
	make -j"$WRT_JOBS" || make -j1 V=s
}

case "$STEP" in
	feeds)    do_feeds ;;
	packages) do_packages ;;
	config)   do_config ;;
	download) do_download ;;
	compile)  do_compile ;;
	all)
		do_feeds
		do_packages
		do_config
		do_download
		do_compile
		;;
	*)
		echo "用法: bash Scripts/build-core.sh <feeds|packages|config|download|compile|all>"
		exit 1
		;;
esac

echo "build-core: [$STEP] 完成"
