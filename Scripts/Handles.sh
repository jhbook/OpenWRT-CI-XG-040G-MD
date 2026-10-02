#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

PKG_PATH="$GITHUB_WORKSPACE/wrt/package/"

# 强制切换到 package 目录，确保所有相对路径生效
cd "$PKG_PATH" || exit 1

#预置HomeProxy数据
if find . -maxdepth 1 -type d -name "*homeproxy*" | grep -q .; then
	echo " "

	HP_RULE="surge"
	HP_PATH="homeproxy/root/etc/homeproxy"

	rm -rf "./$HP_PATH/resources/"*

	git clone -q --depth=1 --single-branch --branch "release" "https://github.com/Loyalsoldier/surge-rules.git" "./$HP_RULE/"
	cd "./$HP_RULE/" && RES_VER=$(git log -1 --pretty=format:'%s' | grep -o "[0-9]*")

	echo "$RES_VER" | tee china_ip4.ver china_ip6.ver china_list.ver gfw_list.ver
	awk -F, '/^IP-CIDR,/{print $2 > "china_ip4.txt"} /^IP-CIDR6,/{print $2 > "china_ip6.txt"}' cncidr.txt
	sed 's/^\.//g' direct.txt > china_list.txt ; sed 's/^\.//g' gfw.txt > gfw_list.txt
	mv -f ./{china_*,gfw_list}.{ver,txt} "../$HP_PATH/resources/"

	cd "$PKG_PATH" && rm -rf "./$HP_RULE/"
	echo "homeproxy date has been updated!"
fi

#修改argon主题字体和颜色
if find . -maxdepth 1 -type d -name "*luci-theme-argon*" | grep -q .; then
	echo " "
	sed -i "s/primary '.*'/primary '#31a1a1'/; s/'0.2'/'0.5'/; s/'none'/'bing'/; s/'600'/'normal'/" ./luci-app-argon-config/root/etc/config/argon
	echo "theme-argon has been fixed!"
fi

#修改aurora菜单式样
if find . -maxdepth 1 -type d -name "*luci-app-aurora-config*" | grep -q .; then
	echo " " && cd ./luci-app-aurora-config/
	# 改用-exec，避免文件过多报参数过长
	find ./root/usr/share/aurora/ -type f -name "*.template" -exec sed -i "s/nav_submenu_type '.*'/nav_submenu_type 'boxed-dropdown'/g" {} +
	cd "$PKG_PATH" && echo "theme-aurora has been fixed!"
fi

#修改mini-diskmanager菜单位置
if find . -maxdepth 1 -type d -name "*luci-app-mini-diskmanager*" | grep -q .; then
	echo " " && cd ./luci-app-mini-diskmanager/
	sed -i "s/services/system/g" ./root/usr/share/luci/menu.d/luci-app-mini-diskmanager.json
	cd "$PKG_PATH" && echo "mini-diskmanager has been fixed!"
fi

#修复TailScale配置文件冲突
TS_FILE=$(find ../feeds/packages/ -maxdepth 3 -type f -wholename "*/tailscale/Makefile")
if [ -f "$TS_FILE" ]; then
	echo " "
	sed -i '/\/files/d' "$TS_FILE"
	echo "tailscale has been fixed!"
fi

#修复Rust编译失败
RUST_FILE=$(find ../feeds/packages/ -maxdepth 3 -type f -wholename "*/rust/Makefile")
if [ -f "$RUST_FILE" ]; then
	echo " "
	sed -i 's/ci-llvm=true/ci-llvm=false/g' "$RUST_FILE"
	echo "rust has been fixed!"
fi

# ========== 编译阶段 feeds.conf.default 浙大源 + 注释pon（解决github action拉feed 404）==========
FEEDS_CONF="$GITHUB_WORKSPACE/wrt/feeds.conf.default"
if [ -f "$FEEDS_CONF" ];then
    # 替换官方github feeds地址为浙大镜像
    sed -i 's#https://github.com/immortalwrt/feeds#https://mirrors.zju.edu.cn/immortalwrt/feeds#g' "$FEEDS_CONF"
    # 注释 pon_drivers pon_userspace（只注释未注释的行，避免重复加#）
    sed -i '/^src-git pon_drivers/s/^/#/' "$FEEDS_CONF"
    sed -i '/^src-git pon_userspace/s/^/#/' "$FEEDS_CONF"
    echo "feeds.conf.default patch done: ZJU mirror & comment pon feeds"
    # 调试输出，Action日志查看修改结果
    cat "$FEEDS_CONF"
fi

# 替换固件内opkg浙大镜像源 注释 pon 源
ROOTFS_FILE="$GITHUB_WORKSPACE/wrt/files/etc/apk/repositories.d/distfeeds.list"
if [ -f "$ROOTFS_FILE" ];then
    sed -i 's#https://downloads.immortalwrt.org#https://mirrors.zju.edu.cn/immortalwrt#g' "$ROOTFS_FILE"
    # 注释所有包含pon_drivers/pon_userspace的行（兼容opkg src/gz格式）
    sed -i '/^#/!{/pon_drivers/s/^/#/}' "$ROOTFS_FILE"
    sed -i '/^#/!{/pon_userspace/s/^/#/}' "$ROOTFS_FILE"
    echo "apk source patch done!"
    cat "$ROOTFS_FILE"
fi
