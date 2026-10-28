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
#   WRT_JOBS       并行任务数（默认 nproc）
#   WRT_SKIP_CLEAN true 时跳过 config 阶段的 make clean

set -euo pipefail

STEP="${1:-all}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- 工作区与源码目录 ----
: "${WRT_WORKSPACE:=$(cd "$SCRIPT_DIR/.." && pwd)}"
: "${WRT_DIR:=$WRT_WORKSPACE/wrt}"
: "${GITHUB_WORKSPACE:=$WRT_WORKSPACE}"
: "${WRT_JOBS:=$(nproc 2>/dev/null || echo 4)}"

# ---- 编译参数默认值（本地编译不传参也能跑）----
: "${WRT_CONFIG:=AIROHA-ONU}"
: "${WRT_THEME:=argon}"
: "${WRT_NAME:=ImmortalWrt}"
: "${WRT_SSID:=ImmortalWrt}"
: "${WRT_WORD:=12345678}"
: "${WRT_IP:=192.168.100.1}"
: "${WRT_PW:=无}"
: "${WRT_PACKAGE:=}"
: "${WRT_TEST:=false}"
: "${WRT_SKIP_CLEAN:=false}"
: "${WRT_MARK:=local}"
: "${WRT_DATE:=$(TZ=UTC-8 date +'%y.%m.%d-%H.%M.%S')}"

CONFIG_FILE="$WRT_WORKSPACE/Config/$WRT_CONFIG.txt"

# 目标平台（Scripts/Settings.sh 依赖）
if [ -z "${WRT_TARGET:-}" ]; then
	WRT_TARGET="$(grep -m 1 -oP '^CONFIG_TARGET_\K[\w]+(?==y)' "$CONFIG_FILE" 2>/dev/null || true)"
	WRT_TARGET="${WRT_TARGET:-none}"
fi

# Scripts/*.sh 依赖 GITHUB_* 变量，本地编译时补齐
if [ -z "${GITHUB_ENV:-}" ] || ! ( : >> "$GITHUB_ENV" ) 2>/dev/null; then
	GITHUB_ENV="$(mktemp -t wrt-build-env.XXXXXX)"
fi

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

	if [[ "${WRT_CONFIG,,}" == *test* ]]; then
		cat "$CONFIG_FILE" >> .config
	else
		cat "$CONFIG_FILE" "$WRT_WORKSPACE/Config/GENERAL.txt" >> .config
	fi

	bash "$WRT_WORKSPACE/Scripts/Settings.sh"

	make defconfig -j"$WRT_JOBS"
	if [ "$WRT_SKIP_CLEAN" != "true" ]; then
		make clean -j"$WRT_JOBS"
	fi
}

do_download() {
	need_source
	cd "$WRT_DIR"
	echo "==> 下载软件包源码"
	make download -j"$WRT_JOBS" || make download -j1 V=s
}

do_compile() {
	need_source
	cd "$WRT_DIR"
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
		if [ "$WRT_TEST" != "true" ]; then
			do_download
			do_compile
		fi
		;;
	*)
		echo "用法: bash Scripts/build-core.sh <feeds|packages|config|download|compile|all>"
		exit 1
		;;
esac

echo "build-core: [$STEP] 完成"
