#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY
#
# 说明：本脚本由 WRT-CORE.yml 的「Custom Packages」步骤执行，工作目录为源码根目录（./wrt）。
#       职责：①用第三方仓库覆盖本地同名插件；②按 GitHub Release 更新 sing-box 版本号与哈希。
set -uo pipefail

GITHUB_API="https://api.github.com"

#安装和更新软件包
UPDATE_PACKAGE() {
	local PKG_NAME=$1
	local PKG_REPO=$2
	local PKG_BRANCH=$3
	local PKG_SPECIAL=${4:-}
	local PKG_LIST=("$PKG_NAME" ${5:-})  # 第5个参数为自定义名称列表
	local REPO_NAME=${PKG_REPO#*/}

	echo " "

	# 删除本地可能存在的不同名称的软件包
	for NAME in "${PKG_LIST[@]}"; do
		[ -n "$NAME" ] || continue

		local FOUND_DIRS
		FOUND_DIRS=$(find ../feeds/luci/ ../feeds/packages/ -maxdepth 3 -type d -iname "*$NAME*" 2>/dev/null)

		if [ -n "$FOUND_DIRS" ]; then
			while read -r DIR; do
				[ -n "$DIR" ] || continue
				#只允许删除 feeds 下的目录，避免变量异常时误删其它路径
				case "$DIR" in
					../feeds/luci/*|../feeds/packages/*)
						rm -rf "$DIR"
						echo "Delete directory: $DIR"
						;;
					*)
						echo "::warning::跳过非 feeds 路径：$DIR"
						;;
				esac
			done <<< "$FOUND_DIRS"
		else
			echo "Not found directory: $NAME"
		fi
	done

	# 克隆 GitHub 仓库：失败直接返回非 0，避免"删掉了却没补回来"却仍然绿灯
	if ! git clone --depth=1 --single-branch --branch "$PKG_BRANCH" "https://github.com/$PKG_REPO.git"; then
		echo "::error::克隆 $PKG_REPO ($PKG_BRANCH) 失败"
		return 1
	fi

	# 处理克隆的仓库
	if [[ "$PKG_SPECIAL" == "pkg" ]]; then
		find ./"$REPO_NAME"/*/ -maxdepth 3 -type d -name "$PKG_NAME" -prune -exec cp -rf {} ./ \;
		rm -rf ./"$REPO_NAME"/
	elif [[ "$PKG_SPECIAL" == "name" ]]; then
		mv -f "$REPO_NAME" "$PKG_NAME"
	fi
}

# 调用示例
# UPDATE_PACKAGE "OpenAppFilter" "destan19/OpenAppFilter" "master" "" "custom_name1 custom_name2"
# UPDATE_PACKAGE "open-app-filter" "destan19/OpenAppFilter" "master" "" "luci-app-appfilter oaf" 这样会把原有的open-app-filter，luci-app-appfilter，oaf相关组件删除，不会出现coremark错误。

# UPDATE_PACKAGE "包名" "项目地址" "项目分支" "pkg/name，可选，pkg为从大杂烩中单独提取包名插件；name为重命名为包名"
UPDATE_PACKAGE "argon" "sbwml/luci-theme-argon" "openwrt-25.12"
#UPDATE_PACKAGE "shadcn" "eamonxg/luci-theme-shadcn" "main"
UPDATE_PACKAGE "aurora" "eamonxg/luci-theme-aurora" "master"
UPDATE_PACKAGE "aurora-config" "eamonxg/luci-app-aurora-config" "master"
#UPDATE_PACKAGE "kucat" "sirpdboy/luci-theme-kucat" "master"
#UPDATE_PACKAGE "kucat-config" "sirpdboy/luci-app-kucat-config" "master"

#UPDATE_PACKAGE "homeproxy" "VIKINGYFY/homeproxy" "main"
#UPDATE_PACKAGE "momo" "nikkinikki-org/OpenWrt-momo" "main"
#UPDATE_PACKAGE "nikki" "nikkinikki-org/OpenWrt-nikki" "main"
#UPDATE_PACKAGE "openclash" "vernesong/OpenClash" "master" "pkg"   # 已在 Config 中关闭，需要时取消注释
#UPDATE_PACKAGE "passwall" "Openwrt-Passwall/openwrt-passwall" "main" "pkg"
#UPDATE_PACKAGE "passwall2" "Openwrt-Passwall/openwrt-passwall2" "main" "pkg"

#UPDATE_PACKAGE "luci-app-tailscale" "asvow/luci-app-tailscale" "main"

#UPDATE_PACKAGE "athena-led" "unraveloop/JDC-AX6600-Athena-LED-Controller" "main"
#UPDATE_PACKAGE "ddns-go" "sirpdboy/luci-app-ddns-go" "main"   # 未在 Config 中启用，需要时取消注释并打开插件
#UPDATE_PACKAGE "diskman" "sbwml/luci-app-diskman" "main"
#UPDATE_PACKAGE "diskmanager" "4IceG/luci-app-mini-diskmanager" "main"
#UPDATE_PACKAGE "easytier" "EasyTier/luci-app-easytier" "main"   # 已在 Config 中关闭，需要时取消注释
#UPDATE_PACKAGE "mosdns" "sbwml/luci-app-mosdns" "v5" "" "v2dat"
#UPDATE_PACKAGE "netspeedtest" "sirpdboy/netspeedtest" "main" "" "homebox ookla-speedtest"
#UPDATE_PACKAGE "netwizard" "sirpdboy/luci-app-netwizard" "main"
#UPDATE_PACKAGE "openlist2" "sbwml/luci-app-openlist2" "main"
#UPDATE_PACKAGE "partexp" "sirpdboy/luci-app-partexp" "main"
#UPDATE_PACKAGE "qbittorrent" "sbwml/luci-app-qbittorrent" "master" "" "qt6base qt6tools rblibtorrent"
#UPDATE_PACKAGE "qmodem" "FUjr/QModem" "main"   # 未在 Config 中启用，需要时取消注释并打开插件
#UPDATE_PACKAGE "quickfile" "sbwml/luci-app-quickfile" "main"
#UPDATE_PACKAGE "timecontrol" "sirpdboy/luci-app-timecontrol" "main"
UPDATE_PACKAGE "viking" "VIKINGYFY/packages" "main" "" "gecoosac luci-app-timewol luci-app-wolplus luci-app-wolultra"
#UPDATE_PACKAGE "vnt" "lmq8267/luci-app-vnt" "main"
UPDATE_PACKAGE "luci-app-airoha-npu" "rchen14b/luci-app-airoha-npu" "main"
# 该仓库根目录即插件本体，内部同名子目录是旧版快照，删除避免出现重复包
rm -rf ./luci-app-airoha-npu/luci-app-airoha-npu/
#UPDATE_PACKAGE "luci-app-lucky" "sirpdboy/luci-app-lucky" "main"   # 已在 Config 中关闭，需要时取消注释
#UPDATE_PACKAGE "luci-app-tailscale-community" "Tokisaki-Galaxy/luci-app-tailscale-community" "master" "" "luci-app-tailscale-community"   # 未在 Config 中启用，需要时取消注释

#更新软件包版本
UPDATE_VERSION() {
	local PKG_NAME=$1
	local PKG_MARK=${2:-false}
	local PKG_FILES
	PKG_FILES=$(find ./ ../feeds/packages/ -maxdepth 5 -type f -path "*/$PKG_NAME/Makefile" 2>/dev/null)

	if [ -z "$PKG_FILES" ]; then
		echo "$PKG_NAME not found!"
		return 0
	fi

	echo -e "\n$PKG_NAME version update has started!"

	# 存在 GITHUB_TOKEN 时带上，避免 API 限流
	local CURL_AUTH=()
	[ -n "${GITHUB_TOKEN:-}" ] && CURL_AUTH=(-H "Authorization: Bearer $GITHUB_TOKEN")

	for PKG_FILE in $PKG_FILES; do
		local PKG_REPO
		PKG_REPO=$(grep -Po "PKG_SOURCE_URL:=https://.*github.com/\K[^/]+/[^/]+(?=.*)" "$PKG_FILE")

		if [ -z "$PKG_REPO" ]; then
			echo "$PKG_FILE: 未解析到 GitHub 仓库地址，跳过"
			continue
		fi

		local PKG_TAG
		PKG_TAG=$(curl -fsSL -H "Accept: application/vnd.github+json" "${CURL_AUTH[@]}" \
			"$GITHUB_API/repos/$PKG_REPO/releases" 2>/dev/null \
			| jq -r "map(select(.prerelease == $PKG_MARK)) | first | .tag_name // empty" 2>/dev/null)

		if [ -z "$PKG_TAG" ] || [ "$PKG_TAG" = "null" ]; then
			echo "$PKG_FILE: 未获取到 Release 版本（$PKG_REPO），跳过"
			continue
		fi

		local OLD_VER OLD_URL OLD_FILE OLD_HASH
		OLD_VER=$(grep -Po "PKG_VERSION:=\K.*" "$PKG_FILE")
		OLD_URL=$(grep -Po "PKG_SOURCE_URL:=\K.*" "$PKG_FILE")
		OLD_FILE=$(grep -Po "PKG_SOURCE:=\K.*" "$PKG_FILE")
		OLD_HASH=$(grep -Po "PKG_HASH:=\K.*" "$PKG_FILE")

		local PKG_URL=$([[ "$OLD_URL" == *"releases"* ]] && echo "${OLD_URL%/}/$OLD_FILE" || echo "${OLD_URL%/}")

		local NEW_VER NEW_URL
		NEW_VER=$(echo "$PKG_TAG" | sed -E 's/[^0-9]+/\./g; s/^\.|\.$//g')
		NEW_URL=$(echo "$PKG_URL" | sed "s/\$(PKG_VERSION)/$NEW_VER/g; s/\$(PKG_NAME)/$PKG_NAME/g")

		# 下载地址仍残留未解析变量时不做更新，否则会出现"新版本号配旧哈希"的错配
		if [[ "$NEW_URL" == *'$('* ]]; then
			echo "$PKG_FILE: 下载地址含未解析变量（$NEW_URL），跳过版本更新"
			continue
		fi

		local NEW_HASH
		NEW_HASH=$(curl -fsSL "$NEW_URL" 2>/dev/null | sha256sum | cut -d ' ' -f 1)

		if [ -z "$NEW_HASH" ]; then
			echo "$PKG_FILE: 下载失败，跳过版本更新（$NEW_URL）"
			continue
		fi

		echo "old version: $OLD_VER $OLD_HASH"
		echo "new version: $NEW_VER $NEW_HASH"

		if [[ "$NEW_VER" =~ ^[0-9].* ]] && dpkg --compare-versions "$OLD_VER" lt "$NEW_VER"; then
			sed -i "s/PKG_VERSION:=.*/PKG_VERSION:=$NEW_VER/g" "$PKG_FILE"
			sed -i "s/PKG_HASH:=.*/PKG_HASH:=$NEW_HASH/g" "$PKG_FILE"
			echo "$PKG_FILE version has been updated!"
		else
			echo "$PKG_FILE version is already the latest!"
		fi
	done
}

#UPDATE_VERSION "软件包名" "测试版，true，可选，默认为否"
UPDATE_VERSION "sing-box"

#引入私有扩展脚本
if [ -f "$GITHUB_WORKSPACE/Scripts/PRIVATE.sh" ]; then
	source "$GITHUB_WORKSPACE/Scripts/PRIVATE.sh"
fi

exit 0
