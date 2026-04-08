# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2012-2015 OpenWrt.org
# Copyright (C) 2016 LEDE Project

# Substituted by SDK, do not remove
# REVISION:=x
# SOURCE_DATE_EPOCH:=x
# BASE_FILES_VERSION:=x
# KERNEL_VERSION:=x
# LIBC_VERSION:=x

# 把与版本/品牌相关的 Kconfig 选项加入依赖跟踪
# 只要这些配置改变（如 VERSION_NUMBER、VERSION_DIST、VERSION_REPO…），依赖它们的目标会自动重建，避免产物里出现过期的版本信息。
# 便于 SDK/单包构建时保持元数据同步与正确性
PKG_CONFIG_DEPENDS += \
	CONFIG_VERSION_HOME_URL \
	CONFIG_VERSION_BUG_URL \
	CONFIG_VERSION_NUMBER \
	CONFIG_VERSION_CODE \
	CONFIG_VERSION_REPO \
	CONFIG_VERSION_DIST \
	CONFIG_VERSION_MANUFACTURER \
	CONFIG_VERSION_MANUFACTURER_URL \
	CONFIG_VERSION_PRODUCT \
	CONFIG_VERSION_SUPPORT_URL \
	CONFIG_VERSION_FIRMWARE_URL \
	CONFIG_VERSION_HWREV \

# 把字符串转小写、把空格/下划线替换为连字符
# 生成安全、规范的标识（用于文件名、URL、目录名等），避免空格/大小写/下划线在 shell、路径或 URL 中带来歧义或不兼容
sanitize = $(call tolower,$(subst _,-,$(subst $(space),-,$(1))))

# VERSION_* 是从 .config 读取各类版本/品牌字段（用 qstrip 去掉多余空白和引号），若未配置则用合理默认

# 对用户友好的发行版本号，例如 23.05.3、22.03.0（未设置时默认为 SNAPSHOT）
# 展示在登录 banner、/etc/os-release、/etc/openwrt_release 的 DISTRIB_RELEASE；也常用于镜像/仓库目录命名与 UI 展示
VERSION_NUMBER:=$(call qstrip,$(CONFIG_VERSION_NUMBER))
# 默认 SNAPSHOT
VERSION_NUMBER:=$(if $(VERSION_NUMBER),$(VERSION_NUMBER),SNAPSHOT)

# 更偏“机器可读/可追溯”的版本标识，通常是提交修订号或代号；未设置时默认为 $(REVISION)（OpenWrt 构建系统自动提供的 rXXXXX-）
# 写入 /etc/openwrt_release 的 DISTRIB_REVISION（或被合成到 os-release 的 VERSION/PRETTY_NAME），便于问题定位与差异比对
VERSION_CODE:=$(call qstrip,$(CONFIG_VERSION_CODE))
# 默认 $(REVISION)（通常是提交版本）
VERSION_CODE:=$(if $(VERSION_CODE),$(VERSION_CODE),$(REVISION))

# 软件包仓库根地址（opkg 的 distfeeds 默认源）
# 用于生成 /etc/opkg/distfeeds.conf（决定 opkg 从哪里拉取包）；也可用于 UI 链接到对应版本软件包目录
VERSION_REPO:=$(call qstrip,$(CONFIG_VERSION_REPO))
# 默认 snapshots 下载地址
VERSION_REPO:=$(if $(VERSION_REPO),$(VERSION_REPO),https://downloads.openwrt.org/snapshots)

# 发行版名称（品牌名），默认 OpenWrt
# os-release 的 NAME、/etc/openwrt_release 的 DISTRIB_ID、banner 等对外品牌展示
VERSION_DIST:=$(call qstrip,$(CONFIG_VERSION_DIST))
# 默认 OpenWrt
VERSION_DIST:=$(if $(VERSION_DIST),$(VERSION_DIST),OpenWrt)
# 将 VERSION_DIST 规范化后的 ID（小写、空格/下划线转为连字符）
# 符合 os-release 对 ID 的要求（小写、无空格等），避免在路径/脚本中出现不兼容字符
VERSION_DIST_SANITIZED:=$(call sanitize,$(VERSION_DIST))

# 厂商/维护者名称，默认 OpenWrt
# 对 OEM/二次发行版进行品牌化，在 About/支持信息中展示
VERSION_MANUFACTURER:=$(call qstrip,$(CONFIG_VERSION_MANUFACTURER))
VERSION_MANUFACTURER:=$(if $(VERSION_MANUFACTURER),$(VERSION_MANUFACTURER),OpenWrt)

# 厂商主页/项目主页链接
# os-release 的 HOME_URL 或 UI 中的“主页”链接
VERSION_MANUFACTURER_URL:=$(call qstrip,$(CONFIG_VERSION_MANUFACTURER_URL))
VERSION_MANUFACTURER_URL:=$(if $(VERSION_MANUFACTURER_URL),$(VERSION_MANUFACTURER_URL),https://openwrt.org/)

# 问题反馈/缺陷跟踪页面
# os-release 的 BUG_REPORT_URL，UI“报告问题”入口
VERSION_BUG_URL:=$(call qstrip,$(CONFIG_VERSION_BUG_URL))
VERSION_BUG_URL:=$(if $(VERSION_BUG_URL),$(VERSION_BUG_URL),https://bugs.openwrt.org/)

# 项目主页（与 Manufacturer URL 区分开，通常是发行版的首页）
# os-release 的 HOME_URL 或帮助页面的跳转
VERSION_HOME_URL:=$(call qstrip,$(CONFIG_VERSION_HOME_URL))
VERSION_HOME_URL:=$(if $(VERSION_HOME_URL),$(VERSION_HOME_URL),https://openwrt.org/)

# 社区/技术支持页面链接
# os-release 的 SUPPORT_URL，UI“获取帮助”链接
VERSION_SUPPORT_URL:=$(call qstrip,$(CONFIG_VERSION_SUPPORT_URL))
VERSION_SUPPORT_URL:=$(if $(VERSION_SUPPORT_URL),$(VERSION_SUPPORT_URL),https://forum.openwrt.org/)

# 固件下载主页或固件目录的入口
# 提供给 UI/脚本跳转到对应固件页面，便于下载或检查更新
VERSION_FIRMWARE_URL:=$(call qstrip,$(CONFIG_VERSION_FIRMWARE_URL))
VERSION_FIRMWARE_URL:=$(if $(VERSION_FIRMWARE_URL),$(VERSION_FIRMWARE_URL),https://downloads.openwrt.org/)

# 产品名（机型/系列名），默认 Generic
# 在 UI、关于信息、镜像描述中提供更细粒度的产品定位；便于 OEM 定制不同机型的对外展示
VERSION_PRODUCT:=$(call qstrip,$(CONFIG_VERSION_PRODUCT))
VERSION_PRODUCT:=$(if $(VERSION_PRODUCT),$(VERSION_PRODUCT),Generic)

# 硬件修订版本，默认 v0
VERSION_HWREV:=$(call qstrip,$(CONFIG_VERSION_HWREV))
# 对同一产品不同硬件修订进行区分，常见于固件适配与说明文档；也可展示在系统信息里
VERSION_HWREV:=$(if $(VERSION_HWREV),$(VERSION_HWREV),v0)

define taint2sym
$(CONFIG_$(firstword $(subst :, ,$(subst +,,$(subst -,,$(1))))))
endef

define taint2name
$(lastword $(subst :, ,$(1)))
endef

# taint 标记体系
# 做什么：
# 	根据一组规则把构建差异编码成标记串 VERSION_TAINTS，例如：
# 		-ALL_KMODS → 如果未启用 ALL_KMODS，则加入 no-all
# 		-IPV6 → 如果未启用 IPV6，则加入 no-ipv6
# 		+USE_GLIBC → 如果启用了 GLIBC，则加入 glibc
# 		…… 宏 taint2sym/taint2name 负责从“+/-符号:标签名”解析出对应的 CONFIG_ 符号和值，再拼出 taints。 同时把相关符号也加入 PKG_CONFIG_DEPENDS，配置变更会触发重建
# 为什么：
# 	把影响 ABI/运行时行为的关键差异“烙印”到版本元数据中，便于包仓库区分、用户识别、问题追溯
# 	避免在不同构建变体之间误混用软件包（如 glibc vs musl、无 IPv6 的镜像等）
VERSION_TAINT_SPECS := \
	-ALL_KMODS:no-all \
	-IPV6:no-ipv6 \
	+USE_GLIBC:glibc \
	+USE_MKLIBS:mklibs \
	+BUSYBOX_CUSTOM:busybox \
	+OVERRIDE_PKGS:override \

# 把构建时的关键差异（如是否启用 IPv6、是否使用 glibc、是否剔除未用库等）汇总为一串标记
# 帮助区分不同构建变体，避免包/镜像跨变体误用，便于问题追溯
VERSION_TAINTS := $(strip $(foreach taint,$(VERSION_TAINT_SPECS), \
	$(if $(findstring +,$(taint)), \
		$(if $(call taint2sym,$(taint)),$(call taint2name,$(taint))), \
		$(if $(call taint2sym,$(taint)),,$(call taint2name,$(taint))) \
	)))

PKG_CONFIG_DEPENDS += $(foreach taint,$(VERSION_TAINT_SPECS),$(call taint2sym,$(taint)))

# 对逗号、反斜杠、单引号、& 做转义，以便安全地放入 sed 替换
# 版本/URL/厂商字符串可能包含这些特殊字符，未转义会让 sed 脚本失效或产生错误替换
# escape commas, backslashes, squotes, and ampersands for sed
define sed_escape
$(subst &,\&,$(subst $(comma),\$(comma),$(subst ','\'',$(subst \,\\,$(1)))))
endef
#'

# 拼装一个通用 sed 命令，把模板中的占位符替换为上面计算好的字段
# %U 仓库 URL
# %V/%v 版本号（原样/下划线+小写）
# %C/%c 版本代码（原样/小写）
# %D/%d 发行名（原样/小写）
# %R 提交版本
# %T/%S/%A 为目标板/子目标/架构包名
# %t 为 taints
# %M/%m 厂商与 URL
# %b/%u/%s/%f 各类链接
# %P 产品名
# %h 硬件修订
# %B 为 SOURCE_DATE_EPOCH
VERSION_SED_SCRIPT:=$(SED) 's,%U,$(call sed_escape,$(VERSION_REPO)),g' \
	-e 's,%V,$(call sed_escape,$(VERSION_NUMBER)),g' \
	-e 's,%v,\L$(call sed_escape,$(subst $(space),_,$(VERSION_NUMBER))),g' \
	-e 's,%C,$(call sed_escape,$(VERSION_CODE)),g' \
	-e 's,%c,\L$(call sed_escape,$(subst $(space),_,$(VERSION_CODE))),g' \
	-e 's,%D,$(call sed_escape,$(VERSION_DIST)),g' \
	-e 's,%d,\L$(call sed_escape,$(subst $(space),_,$(VERSION_DIST))),g' \
	-e 's,%R,$(call sed_escape,$(REVISION)),g' \
	-e 's,%T,$(call sed_escape,$(BOARD)),g' \
	-e 's,%S,$(call sed_escape,$(BOARD)/$(SUBTARGET)),g' \
	-e 's,%A,$(call sed_escape,$(ARCH_PACKAGES)),g' \
	-e 's,%t,$(call sed_escape,$(VERSION_TAINTS)),g' \
	-e 's,%M,$(call sed_escape,$(VERSION_MANUFACTURER)),g' \
	-e 's,%m,$(call sed_escape,$(VERSION_MANUFACTURER_URL)),g' \
	-e 's,%b,$(call sed_escape,$(VERSION_BUG_URL)),g' \
	-e 's,%u,$(call sed_escape,$(VERSION_HOME_URL)),g' \
	-e 's,%s,$(call sed_escape,$(VERSION_SUPPORT_URL)),g' \
	-e 's,%f,$(call sed_escape,$(VERSION_FIRMWARE_URL)),g' \
	-e 's,%P,$(call sed_escape,$(VERSION_PRODUCT)),g' \
	-e 's,%h,$(call sed_escape,$(VERSION_HWREV)),g' \
	-e 's,%B,$(call sed_escape,$(SOURCE_DATE_EPOCH)),g'
