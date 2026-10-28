#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY
#
# 说明：本脚本由 WRT-CORE.yml 的「Custom Packages」步骤执行，工作目录为源码根目录（./wrt）。
#       判断目录是否存在一律用 find，不用 shell glob——`[ -d *"xxx"* ]` 在多个匹配时会报
#       "binary operator expected" 并判假，导致整块修补被静默跳过。
set -uo pipefail

#在多个候选位置里找到第一个存在的包目录（本地克隆的优先，其次 feeds）
find_pkg_dir() {
	local name="$1"
	local dir

	for dir in "./$name" "../feeds/luci/applications/$name" "../feeds/luci/themes/$name"; do
		if [ -d "$dir" ]; then
			printf '%s' "$dir"
			return 0
		fi
	done

	find . ../feeds/luci/applications ../feeds/luci/themes -maxdepth 3 -type d -name "*$name*" 2>/dev/null | head -n 1
}

#预置HomeProxy数据
HP_PKG=$(find_pkg_dir "homeproxy")
if [ -n "$HP_PKG" ]; then
	echo " "

	HP_RULE="surge"
	HP_PATH="$HP_PKG/root/etc/homeproxy"

	if git clone -q --depth=1 --single-branch --branch "release" "https://github.com/Loyalsoldier/surge-rules.git" "./$HP_RULE/"; then
		RES_VER=$(git -C "./$HP_RULE" log -1 --pretty=format:'%s' | grep -o "[0-9]*")

		(
			cd "./$HP_RULE" || exit 1
			echo "$RES_VER" | tee china_ip4.ver china_ip6.ver china_list.ver gfw_list.ver
			awk -F, '/^IP-CIDR,/{print $2 > "china_ip4.txt"} /^IP-CIDR6,/{print $2 > "china_ip6.txt"}' cncidr.txt
			sed 's/^\.//g' direct.txt > china_list.txt
			sed 's/^\.//g' gfw.txt > gfw_list.txt

			#克隆成功后才清空旧资源并写入，避免"先删后建"失败导致资源全空
			if [ -d "../$HP_PATH/resources" ]; then
				rm -rf "${HP_PATH:?}/resources/"*
			fi

			mkdir -p "../$HP_PATH/resources"
			mv -f ./china_ip4.ver ./china_ip4.txt ./china_ip6.ver ./china_ip6.txt \
				./china_list.ver ./china_list.txt ./gfw_list.ver ./gfw_list.txt \
				"../$HP_PATH/resources/" 2>/dev/null || true
		)

		rm -rf "./$HP_RULE/"
		echo "homeproxy date has been updated!"
	else
		echo "::warning::surge-rules 克隆失败，跳过 homeproxy 资源更新"
	fi
fi

#修改argon主题字体和颜色
ARGON_PKG=$(find_pkg_dir "luci-theme-argon")
if [ -n "$ARGON_PKG" ]; then
	echo " "

	ARGON_CONF="$ARGON_PKG/luci-app-argon-config/root/etc/config/argon"
	if [ -f "$ARGON_CONF" ]; then
		sed -i "s/primary '.*'/primary '#31a1a1'/; s/'0.2'/'0.5'/; s/'none'/'bing'/; s/'600'/'normal'/" "$ARGON_CONF"
		echo "theme-argon has been fixed!"
	else
		echo "::warning::未找到 argon 配置文件，跳过主题修补"
	fi
fi

#修改aurora菜单式样
AURORA_PKG=$(find_pkg_dir "luci-app-aurora-config")
if [ -n "$AURORA_PKG" ]; then
	echo " "

	AURORA_FILES=$(find "$AURORA_PKG/root/usr/share/aurora/" -type f -name "*.template" 2>/dev/null)
	if [ -n "$AURORA_FILES" ]; then
		# shellcheck disable=SC2086
		sed -i "s/nav_submenu_type '.*'/nav_submenu_type 'boxed-dropdown'/g" $AURORA_FILES
		echo "theme-aurora has been fixed!"
	fi
fi

#修改mini-diskmanager菜单位置
MDM_PKG=$(find_pkg_dir "luci-app-mini-diskmanager")
if [ -n "$MDM_PKG" ]; then
	echo " "

	MDM_MENU="$MDM_PKG/root/usr/share/luci/menu.d/luci-app-mini-diskmanager.json"
	if [ -f "$MDM_MENU" ]; then
		sed -i "s/services/system/g" "$MDM_MENU"
		echo "mini-diskmanager has been fixed!"
	fi
fi

#修复TailScale配置文件冲突（feeds 目录层级较深，放宽 maxdepth）
TS_FILE=$(find ../feeds/packages/ -maxdepth 5 -type f -path "*/tailscale/Makefile" 2>/dev/null | head -n 1)
if [ -n "$TS_FILE" ] && [ -f "$TS_FILE" ]; then
	echo " "

	sed -i '/\/files/d' "$TS_FILE"
	echo "tailscale has been fixed!"
fi

#修复Rust编译失败
RUST_FILE=$(find ../feeds/packages/ -maxdepth 5 -type f -path "*/rust/Makefile" 2>/dev/null | head -n 1)
if [ -n "$RUST_FILE" ] && [ -f "$RUST_FILE" ]; then
	echo " "

	sed -i 's/ci-llvm=true/ci-llvm=false/g' "$RUST_FILE"
	echo "rust has been fixed!"
fi

exit 0
