#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY
#
# 说明：本脚本由 WRT-CORE.yml 的「Custom Settings」步骤执行，工作目录为源码根目录（./wrt）。
#       所有修改都必须"目标存在才动手"，否则非 airoha 平台（X86/IPQ/ROCKCHIP 等）会因 sed 找不到文件而失败。
set -uo pipefail

#变量兜底，避免 set -u 下未定义直接报错
: "${WRT_THEME:=argon}"
: "${WRT_NAME:=OWRT}"
: "${WRT_SSID:=OWRT}"
: "${WRT_WORD:=12345678}"
: "${WRT_IP:=192.168.1.1}"
: "${WRT_MARK:=OWRT}"
: "${WRT_DATE:=$(date +%Y%m%d)}"
: "${WRT_TARGET:=}"
: "${WRT_CONFIG:=}"
: "${WRT_PACKAGE:=}"

#统一的"找到文件才执行 sed"，避免 find 结果为空时 sed 报错（sed: no input files）
sed_find() {
	local pattern="$1"
	local dir="$2"
	local expr="$3"
	local files

	files=$(find "$dir" -type f -name "$pattern" 2>/dev/null)
	[ -z "$files" ] && return 0

	# shellcheck disable=SC2086
	sed -i "$expr" $files
}

#转义 sed 替换串中的特殊字符（/ 与 &）
sed_escape() {
	printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'
}

#移除luci-app-attendedsysupgrade
sed_find "Makefile" "./feeds/luci/collections/" "/attendedsysupgrade/d"
#修改默认主题
sed_find "Makefile" "./feeds/luci/collections/" "s/luci-theme-bootstrap/luci-theme-$WRT_THEME/g"
#修改immortalwrt.lan关联IP
sed_find "flash.js" "./feeds/luci/modules/luci-mod-system/" "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g"
#添加编译日期标识
sed_find "10_system.js" "./feeds/luci/modules/luci-mod-status/" "s/(\(luciversion || ''\))/(\1) + (' \/ $WRT_MARK-$WRT_DATE')/g"

#修改WIFI名称/密码（按平台不同，可能是 uci-defaults 脚本或 mac80211.uc）
WIFI_SH=$(find ./target/linux/mediatek/filogic ./target/linux/qualcommax -type f -name "*set-wireless.sh" 2>/dev/null)
WIFI_UC="./package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"

WRT_SSID_ESC=$(sed_escape "$WRT_SSID")
WRT_WORD_ESC=$(sed_escape "$WRT_WORD")

if [ -n "$WIFI_SH" ]; then
	while read -r SH_FILE; do
		[ -f "$SH_FILE" ] || continue
		#修改WIFI名称
		sed -i "s/BASE_SSID='.*'/BASE_SSID='$WRT_SSID_ESC'/g" "$SH_FILE"
		#修改WIFI密码
		sed -i "s/BASE_WORD='.*'/BASE_WORD='$WRT_WORD_ESC'/g" "$SH_FILE"
	done <<< "$WIFI_SH"
elif [ -f "$WIFI_UC" ]; then
	#只替换赋值号后的单引号内容，避免贪婪匹配跨字段吞行破坏 uc 语法
	sed -i "s/\(ssid=\)'[^']*'/\1'$WRT_SSID_ESC'/g" "$WIFI_UC"
	sed -i "s/\(key=\)'[^']*'/\1'$WRT_WORD_ESC'/g" "$WIFI_UC"
	sed -i "s/\(country=\)'[^']*'/\1'CN'/g" "$WIFI_UC"
	sed -i "s/\(encryption=\)'[^']*'/\1'psk2+ccmp'/g" "$WIFI_UC"
else
	echo "::warning::未找到 WIFI 默认配置文件，跳过 WIFI 名称/密码修改"
fi

CFG_FILE="./package/base-files/files/bin/config_generate"
if [ -f "$CFG_FILE" ]; then
	#修改默认IP地址
	sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" "$CFG_FILE"
	#修改默认主机名
	sed -i "s/hostname='.*'/hostname='$WRT_NAME'/g" "$CFG_FILE"
else
	echo "::warning::未找到 config_generate，跳过默认 IP/主机名修改"
fi

#配置文件修改
{
	echo "CONFIG_PACKAGE_luci=y"
	echo "CONFIG_LUCI_LANG_zh_Hans=y"
	echo "CONFIG_PACKAGE_luci-theme-$WRT_THEME=y"
	echo "CONFIG_PACKAGE_luci-app-$WRT_THEME-config=y"
} >> ./.config

#引入私有扩展配置
if [ -f "$GITHUB_WORKSPACE/Config/PRIVATE.txt" ]; then
	echo "Applying private configurations from PRIVATE.txt..."
	cat "$GITHUB_WORKSPACE/Config/PRIVATE.txt" >> ./.config
fi

#手动调整的插件
if [ -n "$WRT_PACKAGE" ]; then
	echo -e "$WRT_PACKAGE" >> ./.config
fi

#高通平台调整
DTS_PATH="./target/linux/qualcommax/dts/"
if [[ "${WRT_TARGET^^}" == *"QUALCOMMAX"* ]]; then
	#取消nss相关feed
	echo "CONFIG_FEED_nss_packages=n" >> ./.config
	echo "CONFIG_FEED_sqm_scripts_nss=n" >> ./.config
	#设置NSS版本
	echo "CONFIG_NSS_FIRMWARE_VERSION_12_5=y" >> ./.config
	#其他调整
	echo "CONFIG_PACKAGE_kmod-usb-serial-qualcomm=y" >> ./.config

	#无WIFI配置调整Q6大小
	if [[ "${WRT_CONFIG,,}" == *"wifi"* && "${WRT_CONFIG,,}" == *"no"* ]]; then
		find $DTS_PATH -type f ! -iname '*nowifi*' -exec sed -i 's/ipq\(6018\|8074\).dtsi/ipq\1-nowifi.dtsi/g' {} +
		echo "qualcommax set up nowifi successfully!"
	fi
fi

#调整网口顺序与中断参数（仅 airoha 平台存在这些文件，其它平台直接跳过）
AIROHA_NETWORK="target/linux/airoha/an7581/base-files/etc/board.d/02_network"
AIROHA_DTS="target/linux/airoha/dts/an7581-nokia_xg-040g-md-common.dtsi"

if [ -f "$AIROHA_NETWORK" ]; then
	sed -i 's/ucidef_set_interface_lan "lan1 lan2 lan3 lan4"/ucidef_set_interfaces_lan_wan "lan1 lan2 lan3" "lan4"/g' "$AIROHA_NETWORK"
fi

if [ -f "$AIROHA_DTS" ]; then
	sed -i 's/interrupts.*//g' "$AIROHA_DTS"
fi

exit 0
