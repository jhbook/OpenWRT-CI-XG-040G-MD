#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

# 本地 / 远程 Ubuntu 一键编译脚本，复用云编译同一套流程（Scripts/build-core.sh）
# 用法示例:
#   bash Scripts/local-build.sh --test              # 只拉源码+插件+生成配置，验证环境
#   bash Scripts/local-build.sh                     # 完整编译 AIROHA-ONU
#   bash Scripts/local-build.sh -c X86 -j 4         # 编译 X86 配置，4 并行
#   bash Scripts/local-build.sh -c AIROHA-ONU --menuconfig

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRT_WORKSPACE="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---- 默认参数（可用环境变量覆盖）----
: "${WRT_CONFIG:=AIROHA-ONU}"
: "${WRT_REPO:=pbs05/ponwrt}"
: "${WRT_BRANCH:=master}"
: "${WRT_THEME:=argon}"
: "${WRT_NAME:=ImmortalWrt}"
: "${WRT_SSID:=ImmortalWrt}"
: "${WRT_WORD:=12345678}"
: "${WRT_IP:=192.168.100.1}"
: "${WRT_PW:=无}"
WRT_PACKAGE="${WRT_PACKAGE:-}"
WRT_TEST="false"
WRT_JOBS="$(nproc 2>/dev/null || echo 4)"
WRT_SKIP_CLEAN="false"

SRC_DIR=""
MENUCONFIG="false"
INSTALL_DEPS="false"
SKIP_DEPS="false"
FORCE_CLONE="false"
PROXY_URL=""

DEPS=(build-essential clang flex bison g++ gawk gcc-multilib g++-multilib gettext git \
	libncurses-dev libssl-dev python3-setuptools python3-dev rsync swig unzip zlib1g-dev \
	file wget libelf-dev jq)

usage() {
	cat <<'EOF'
用法: bash Scripts/local-build.sh [选项]

选项:
  -c, --config NAME    配置名，对应 Config/NAME.txt（默认 AIROHA-ONU）
  -d, --dir DIR        源码目录（默认 ~/openwrt-build/小写配置名）
  -r, --repo REPO      源码仓库（默认 pbs05/ponwrt）
  -b, --branch NAME    源码分支（默认 master）
  -j, --jobs N         并行任务数（默认 nproc）
  -p, --package TEXT   追加到 .config 的插件配置
  -t, --test           只生成配置，不下载不编译
  -m, --menuconfig     生成配置后进入 make menuconfig
      --install-deps   自动安装缺失的编译依赖（需要 sudo）
      --skip-deps      跳过编译依赖检查（--test 只生成配置时可跳过）
      --force-clone    删除已有源码目录并重新 clone
      --proxy URL      GitHub 加速前缀，例如 https://ghfast.top/
                       （本次运行内所有 github 克隆都走加速，不修改 git 全局配置）
  -h, --help           显示帮助

环境变量 WRT_THEME / WRT_NAME / WRT_SSID / WRT_WORD / WRT_IP / WRT_PW 可覆盖默认固件参数。
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
		-c|--config)   WRT_CONFIG="${2:?缺少配置名}"; shift 2 ;;
		-d|--dir)      SRC_DIR="${2:?缺少目录}"; shift 2 ;;
		-r|--repo)     WRT_REPO="${2:?缺少仓库}"; shift 2 ;;
		-b|--branch)   WRT_BRANCH="${2:?缺少分支}"; shift 2 ;;
		-j|--jobs)     WRT_JOBS="${2:?缺少并行数}"; shift 2 ;;
		-p|--package)  WRT_PACKAGE="${2:?缺少插件配置}"; shift 2 ;;
		-t|--test)     WRT_TEST="true"; shift ;;
		-m|--menuconfig) MENUCONFIG="true"; shift ;;
		--install-deps) INSTALL_DEPS="true"; shift ;;
		--skip-deps)   SKIP_DEPS="true"; shift ;;
		--force-clone) FORCE_CLONE="true"; shift ;;
		--proxy)       PROXY_URL="${2:?缺少代理地址}"; shift 2 ;;
		-h|--help)     usage; exit 0 ;;
		*)             echo "未知参数: $1"; usage; exit 1 ;;
	esac
done

[ -n "$SRC_DIR" ] || SRC_DIR="$HOME/openwrt-build/$(echo "$WRT_CONFIG" | tr '[:upper:]' '[:lower:]')"
if [ "$WRT_CONFIG" != *test* ] && [ "$WRT_TEST" != "true" ]; then
	:
fi

CONFIG_FILE="$WRT_WORKSPACE/Config/$WRT_CONFIG.txt"
if [ ! -f "$CONFIG_FILE" ]; then
	echo "错误: 配置文件不存在: $CONFIG_FILE"
	echo "可用配置:"
	for FILE in "$WRT_WORKSPACE"/Config/*.txt; do
		echo "  - $(basename "$FILE" .txt)"
	done
	exit 1
fi

check_deps() {
	if [ "$SKIP_DEPS" = "true" ]; then
		echo "==> 已跳过编译依赖检查（--skip-deps）"
		return
	fi

	local MISSING=()
	for PKG in "${DEPS[@]}"; do
		if ! dpkg -s "$PKG" >/dev/null 2>&1; then
			MISSING+=("$PKG")
		fi
	done

	if [ "${#MISSING[@]}" -eq 0 ]; then
		echo "==> 编译依赖检查通过"
		return
	fi

	echo "==> 缺少编译依赖: ${MISSING[*]}"
	if [ "$INSTALL_DEPS" = "true" ]; then
		sudo apt update
		sudo apt install -y "${MISSING[@]}"
	else
		echo "   可执行 sudo apt install -y ${MISSING[*]}"
		echo "   或加 --install-deps 自动安装"
		exit 1
	fi
}

check_disk() {
	local NEED=25
	[ "$WRT_TEST" = "true" ] && NEED=6

	local TARGET_DIR="$SRC_DIR"
	[ -d "$TARGET_DIR" ] || TARGET_DIR="$(dirname "$TARGET_DIR")"
	[ -d "$TARGET_DIR" ] || TARGET_DIR="$HOME"

	local AVAIL
	AVAIL="$(df -Pk "$TARGET_DIR" | awk 'NR==2 {printf "%d", $4/1048576}')"
	echo "==> 磁盘可用 ${AVAIL}G（$WRT_TEST 模式约需 ${NEED}G）"
	if [ "$AVAIL" -lt "$NEED" ]; then
		echo "错误: 磁盘空间不足，请清理空间或用 --dir 指定更大分区"
		exit 1
	fi
}

prepare_source() {
	if [ "$FORCE_CLONE" = "true" ] && [ -d "$SRC_DIR" ]; then
		echo "==> 删除旧源码目录: $SRC_DIR"
		rm -rf "$SRC_DIR"
	fi

	if [ -d "$SRC_DIR/.git" ]; then
		echo "==> 复用已有源码目录: $SRC_DIR"
		return
	fi

	mkdir -p "$(dirname "$SRC_DIR")"
	echo "==> 克隆源码: https://github.com/$WRT_REPO.git ($WRT_BRANCH)"
	git clone --depth=1 --single-branch --branch "$WRT_BRANCH" \
		"https://github.com/$WRT_REPO.git" "$SRC_DIR"
	# 说明: 本地编译保留源码内置的国内下载源（只有 GitHub 云端才会移除），下载更快
}

# GitHub 加速前缀：只对本次运行的 git 生效，不写入用户 git 全局配置
if [ -n "$PROXY_URL" ]; then
	export GIT_CONFIG_COUNT=1
	export GIT_CONFIG_KEY_0="url.${PROXY_URL}https://github.com/.insteadOf"
	export GIT_CONFIG_VALUE_0="https://github.com/"
	echo "==> GitHub 加速前缀: $PROXY_URL"
fi

echo "==> 配置: $WRT_CONFIG | 源码: $WRT_REPO ($WRT_BRANCH) | 目录: $SRC_DIR"
echo "==> 模式: $([ "$WRT_TEST" = "true" ] && echo 仅生成配置 || echo 完整编译) | 并行: $WRT_JOBS"

check_deps
check_disk
prepare_source

export WRT_WORKSPACE
export WRT_DIR="$SRC_DIR"
export WRT_CONFIG WRT_THEME WRT_NAME WRT_SSID WRT_WORD WRT_IP WRT_PW WRT_PACKAGE
export WRT_JOBS WRT_TEST WRT_SKIP_CLEAN

CORE="$WRT_WORKSPACE/Scripts/build-core.sh"

bash "$CORE" feeds
bash "$CORE" packages
bash "$CORE" config

if [ "$MENUCONFIG" = "true" ]; then
	( cd "$SRC_DIR" && make menuconfig )
fi

if [ "$WRT_TEST" != "true" ]; then
	bash "$CORE" download
	bash "$CORE" compile
fi

echo "=================================================="
if [ "$WRT_TEST" = "true" ]; then
	echo "配置已生成: $SRC_DIR/.config"
	echo "目标平台: $(grep -m 1 -oP '^CONFIG_TARGET_BOARD="\K[^"]+' "$SRC_DIR/.config" 2>/dev/null || echo 未知)"
	echo "启用插件数: $(grep -c '^CONFIG_PACKAGE_luci-app.*=y' "$SRC_DIR/.config" 2>/dev/null || echo 0)"
	echo "确认无误后执行完整编译:"
	echo "  bash Scripts/local-build.sh -c $WRT_CONFIG -d $SRC_DIR"
else
	echo "编译完成，固件目录: $SRC_DIR/bin/targets"
	find "$SRC_DIR/bin/targets" -type f \( -name "*.bin" -o -name "*.img*" -o -name "*.itb" -o -name "*.tar" \) 2>/dev/null | head -20 || true
fi
echo "=================================================="
