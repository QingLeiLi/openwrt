# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2014 OpenWrt.org
# Copyright (C) 2016 LEDE Project

# 可选地引入构建过程中导出的辅助变量（如各包的 ABIV_* 覆盖值）
# 把自动探测或上游生成的信息注入后续规则，避免硬编码
# 内容示例，一般来自各包 Makefile 里的 ABI_VERSION
# ABIV_libubox:=20231212
# ABIV_libopenssl:=1.1
# ABIV_libfoo:=2
-include $(TMP_DIR)/.packageauxvars

# 获取 package/feeds 下所有的文件,作为已安装的 feed
FEEDS_INSTALLED:=$(notdir $(wildcard $(TOPDIR)/package/feeds/*))
# 在已安装基础上，再并入脚本 feeds list -n 的输出，得到“可用 feed 的全集（去重后排序）”
FEEDS_AVAILABLE:=$(sort $(FEEDS_INSTALLED) $(shell $(SCRIPT_DIR)/feeds list -n 2>/dev/null))

# 默认只有 $(PACKAGE_DIR)
PACKAGE_SUBDIRS=$(PACKAGE_DIR)
# 按 feed 切分包仓库（distfeeds），便于发布、镜像拆分与权限/缓存管理；未启用时保持传统单仓布局
ifneq ($(CONFIG_PER_FEED_REPO),)
  # 额外加入 base 子仓库
  PACKAGE_SUBDIRS += $(OUTPUT_DIR)/packages/$(ARCH_PACKAGES)/base
  # 为每个 feed 加一个子仓库
  PACKAGE_SUBDIRS += $(foreach FEED,$(FEEDS_AVAILABLE),$(OUTPUT_DIR)/packages/$(ARCH_PACKAGES)/$(FEED))
endif

# 在所有 PACKAGE_SUBDIRS 下匹配给定包名列表，收集对应的 .ipk 文件路径
opkg_package_files = $(wildcard \
	$(foreach dir,$(PACKAGE_SUBDIRS), \
	  $(foreach pkg,$(1), $(dir)/$(pkg)_*.ipk)))

# 在所有 PACKAGE_SUBDIRS 下匹配给定包名列表，收集对应的 .apk 文件路径
apk_package_files = $(wildcard \
	$(foreach dir,$(PACKAGE_SUBDIRS), \
	  $(foreach pkg,$(1), $(dir)/$(pkg)-*.apk)))

# 返回某个包应该落盘到哪个目录
# 未启用 PER_FEED：一律落到 $(PACKAGE_DIR)
# 启用 PER_FEED：
# 	若包定义了 Package/xx/subdir，则用该 subdir 对应的仓库目录
# 	否则仍落到 $(PACKAGE_DIR)（通常是本地 staging 区）
# CONFIG_PER_FEED_REPO 允许细粒度地为某些包指定目标仓库（例如把 Toolchain/SDK 相关包塞到 base）
# 1: package name
define FeedPackageDir
$(strip $(if $(CONFIG_PER_FEED_REPO), \
  $(if $(Package/$(1)/subdir), \
    $(abspath $(OUTPUT_DIR)/packages/$(ARCH_PACKAGES)/$(Package/$(1)/subdir)), \
    $(PACKAGE_DIR)), \
  $(PACKAGE_DIR)))
endef

# 生成 distfeeds 源列表
# 把 opkg 的 feed 源行追加到目标文件 dest
# 核心 feed：src/gz %d_core %U/targets/%S/packages
# 若启用 PER_FEED：
# 	基础包仓库：src/gz %d_base %U/packages/%A/base
# 	若 CONFIG_BUILDBOT：为 kmods 生成“按内核 ABI 锁定”的源
# 	对每个开启的 feed 生成一行：
# 		若 CONFIG_FEED_=y：正常启用
# 		若为 m：在行首加“# ”注释掉，用户可手动解注启用
# 		形如：src/gz %d_ %U/packages/%A/
# 1: destination file
define FeedSourcesAppendOPKG
( \
  echo 'src/gz %d_core %U/targets/%S/packages'; \
  $(strip $(if $(CONFIG_PER_FEED_REPO), \
	echo 'src/gz %d_base %U/packages/%A/base'; \
	$(if $(CONFIG_BUILDBOT), \
		echo 'src/gz %d_kmods %U/targets/%S/kmods/$(LINUX_VERSION)-$(LINUX_RELEASE)-$(LINUX_VERMAGIC)';) \
	$(foreach feed,$(FEEDS_AVAILABLE), \
		$(if $(CONFIG_FEED_$(feed)), \
			echo '$(if $(filter m,$(CONFIG_FEED_$(feed))),# )src/gz %d_$(feed) %U/packages/%A/$(feed)';)))) \
) >> $(1)
endef

# 同 OPKG 逻辑但面向 APK 索引，直接追加 ADB 索引文件路径
# 	%U/targets/%S/packages/packages.adb
# 	以及 base、kmods、各 feed 的 packages.adb
# 1: destination file
define FeedSourcesAppendAPK
( \
  echo '%U/targets/%S/packages/packages.adb'; \
  $(strip $(if $(CONFIG_PER_FEED_REPO), \
	echo '%U/packages/%A/base/packages.adb'; \
	$(if $(CONFIG_BUILDBOT), \
		echo '%U/targets/%S/kmods/$(LINUX_VERSION)-$(LINUX_RELEASE)-$(LINUX_VERMAGIC)/packages.adb';) \
	$(foreach feed,$(FEEDS_AVAILABLE), \
		$(if $(CONFIG_FEED_$(feed)), \
			echo '$(if $(filter m,$(CONFIG_FEED_$(feed))),# )%U/packages/%A/$(feed)/packages.adb';)))) \
) >> $(1)
endef

# 计算包的 ABI 后缀
# 默认从构建时生成的元信息推导，保证一致性；但是允许手动覆盖 ABI
# 规则：
# 	若存在显式覆盖 ABIV_，优先返回该值
# 	否则从 $(STAGING_DIR)/pkginfo/.version 读取版本号，交给 FormatABISuffix(name, version) 形成后缀
# 1: package name
define GetABISuffix
$(if $(ABIV_$(1)),$(ABIV_$(1)),$(call FormatABISuffix,$(1),$(foreach v,$(wildcard $(STAGING_DIR)/pkginfo/$(1).version),$(shell cat $(v)))))
endef

# 把 abi 版本转成可拼接的后缀
# kmod-% 包直接不加后缀（内核模块的 ABI 由 kmods 仓库路径锁定，不在包名层面重复表达）
# 对非 kmod 包，若存在 abi_version：
# 	若包名以数字结尾（如 libfoo2），在 abi 前加连字符：-
# 	否则直接拼接 实现上用 filter 判断“是否以数字结尾”
# 示例：
# libfoo + 1 → libfoo1（无连字符）
# libfoo2 + 1 → libfoo2-1（加连字符避免与原尾部数字黏连产生歧义）
# 1: package name
# 2: abi version
define FormatABISuffix
$(if
	# filter-out 是删除所有能匹配模式 kmod-% 的单词。返回剩下的单词
	# 如果返回有内容，说明不是 内核模块，需要追加 abi 后缀
	# 如果没有返回内容，说明是内核模块，上面的 if 没有 else，什么都不做
	$(filter-out
		kmod-%,
		$(1)
	),
	$(if
		$(2),
		$(if
			# 判断是否以数字结尾
			$(filter
				%0 %1 %2 %3 %4 %5 %6 %7 %8 %9,
				$(1)
			),
		# 以数字结尾需要加 - 连字符
		# 这里第一个 ) 是匹配 if 的，if 负责控制是否返回 -，$(2) 会一直都在
		-)$(2)
	)
)
endef
