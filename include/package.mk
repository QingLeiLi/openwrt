# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2006-2020 OpenWrt.org

# OpenWrt包构建系统的主要框架文件，定义了如何编译、安装和打包软件包。

# 设置一个标志变量，表示这个package.mk文件已经被包含，用于一些能力检测吧，包含了这个文件，就可以使用 package.mk 定义的功能
__package_mk:=1

# 默认目标all
# dumpinfo目标定义在：openwrt/include/package-dumpinfo.mk
all: $(if $(DUMP),dumpinfo,$(if $(CHECK),check,compile))

include $(INCLUDE_DIR)/download.mk

# 包构建目录
# BUILD_DIR    变种目录       包名      版本后缀
PKG_BUILD_DIR ?= $(BUILD_DIR)/$(if $(BUILD_VARIANT),$(PKG_NAME)-$(BUILD_VARIANT)/)$(PKG_NAME)$(if $(PKG_VERSION),-$(PKG_VERSION))
# 包安装目录
PKG_INSTALL_DIR ?= $(PKG_BUILD_DIR)/ipkg-install
# 并行构建设置，默认为空，由外部指定
PKG_BUILD_PARALLEL ?=
# 是否跳过 download，如果使用 USE_SOURCE_DIR、USE_GIT_TREE、USE_GIT_SRC_CHECKOUT 三种方式中的任何一种，就跳过 download
PKG_SKIP_DOWNLOAD=$(USE_SOURCE_DIR)$(USE_GIT_TREE)$(USE_GIT_SRC_CHECKOUT)

# 设置make并行参数
# make版本是3.x或4.0/4.1，则添加-j参数
MAKE_J:=$(if $(MAKE_JOBSERVER),$(MAKE_JOBSERVER) $(if $(filter 3.% 4.0 4.1,$(MAKE_VERSION)),-j))

# 获取源码日期时间戳，用于可重现构建。只在非DUMP模式下执行
PKG_SOURCE_DATE_EPOCH:=$(if $(DUMP),,$(shell $(TOPDIR)/scripts/get_source_date_epoch.sh $(CURDIR)))

# 如果 PKG_BUILD_PARALLEL 为0，强制单线程编译(-j1)
ifeq ($(strip $(PKG_BUILD_PARALLEL)),0)
PKG_JOBS?=-j1
else
# 如果设置了并行构建，使用MAKE_J，否则单线程
PKG_JOBS?=$(if $(PKG_BUILD_PARALLEL),$(MAKE_J),-j1)
endif

# 存储构建标志
PKG_BUILD_FLAGS?=
# 构建标志验证，白名单机制
__unknown_flags=$(filter-out no-iremap no-mips16 gc-sections no-gc-sections lto no-lto no-mold,$(PKG_BUILD_FLAGS))
# 如果有未知标志，报错退出
ifneq ($(__unknown_flags),)
  $(error unknown PKG_BUILD_FLAGS: $(__unknown_flags))
endif

# 标志处理函数
# 如果 PKG_BUILD_FLAGS 中存在 no-<flag>，则返回 0，
# 如果存在 <flag>，则返回 1
# 否则返回 $2 默认值
# $1=flagname, $2=default (0/1)
define pkg_build_flag
$(if
  # 如果 PKG_BUILD_FLAGS 中存在 no-<flag>
  $(filter no-$(1), $(PKG_BUILD_FLAGS)),
  0,
  $(if
    # 如果 PKG_BUILD_FLAGS 中存在 <flag>
    $(filter $(1), $(PKG_BUILD_FLAGS)),
    1,
    $(2)
  )
)
endef

# IREMAP支持（路径重映射）
# 获取 iremap flag 是否设置
ifeq ($(call pkg_build_flag,iremap,1),1)
  # 获取相应的CFLAGS，用于调试信息中的路径标准化
  # iremap 函数定义在 openwrt/rules.mk 中
  IREMAP_CFLAGS = $(call iremap,$(PKG_BUILD_DIR),$(notdir $(PKG_BUILD_DIR)))
  TARGET_CFLAGS += $(IREMAP_CFLAGS)
endif

# 如果系统配置使用 MIPS16
ifdef CONFIG_USE_MIPS16
  # 包启用mips16标志
  ifeq ($(call pkg_build_flag,mips16,1),1)
    # 移除mips16相关选项
    TARGET_ASFLAGS_DEFAULT = $(filter-out -mips16 -minterlink-mips16,$(TARGET_CFLAGS))
    # 为C/C++编译添加MIPS16指令集支持
    TARGET_CFLAGS += -mips16 -minterlink-mips16
    TARGET_CXXFLAGS += -mips16 -minterlink-mips16
  endif
endif

# 垃圾回收段优化
ifeq ($(call pkg_build_flag,gc-sections,$(if $(CONFIG_USE_GC_SECTIONS),1,0)),1)
  # 编译时将函数和数据放入独立段
  TARGET_CFLAGS+= -ffunction-sections -fdata-sections
  TARGET_CXXFLAGS+= -ffunction-sections -fdata-sections
  # 链接时移除未使用的段，减小二进制大小
  TARGET_LDFLAGS+= -Wl,--gc-sections
endif

# LTO 链接时优化
ifeq ($(call pkg_build_flag,lto,$(if $(CONFIG_USE_LTO),1,0)),1)
  # 添加 LTO 编译和链接标志
  # auto 表示自动检测并行度，fno-fat-lto-objects 减小目标文件大小
  TARGET_CFLAGS+= -flto=auto -fno-fat-lto-objects
  TARGET_CXXFLAGS+= -flto=auto -fno-fat-lto-objects
  TARGET_LDFLAGS+= -flto=auto -fuse-linker-plugin
endif

# MOLD 链接器支持
ifdef CONFIG_USE_MOLD
  ifeq ($(call pkg_build_flag,mold,1),1)
    TARGET_LINKER:=mold
  endif
endif

# 安全加固
include $(INCLUDE_DIR)/hardening.mk
# 先决条件检查
include $(INCLUDE_DIR)/prereq.mk
# 源码解压功能
include $(INCLUDE_DIR)/unpack.mk
# 依赖关系处理
include $(INCLUDE_DIR)/depends.mk

# 如果存在git-src目录
ifneq ($(wildcard $(TOPDIR)/git-src/$(PKG_NAME)/.git),)
  # 使用 Git 源码检出
  USE_GIT_SRC_CHECKOUT:=1
  # 启用 QUILT 补丁管理
  QUILT:=1
endif

# 如果配置了源码树覆盖
ifneq ($(if $(CONFIG_SRC_TREE_OVERRIDE),$(wildcard ./git-src)),)
  # 使用 Git 树
  USE_GIT_TREE:=1
  QUILT:=1
endif

# 如果使用源码目录，启用QUILT
ifdef USE_SOURCE_DIR
  QUILT:=1
endif

# 如果存在 .source_dir 文件，启用QUILT
ifneq ($(wildcard $(PKG_BUILD_DIR)/.source_dir),)
  QUILT:=1
endif

include $(INCLUDE_DIR)/quilt.mk

# 递归查找库依赖关系
find_library_dependencies = \
  # 返回 staging 目录中存在的依赖包版本文件
	$(wildcard $(patsubst %,$(STAGING_DIR)/pkginfo/%.version, \
    # 排除正在构建的包，避免循环依赖
    # 最多5层递归
		$(filter-out $(BUILD_PACKAGES), $(sort $(foreach dep4, \
			$(sort $(foreach dep3, \
				$(sort $(foreach dep2, \
					$(sort $(foreach dep1, \
            # 从包的直接依赖开始（dep0）
            # 在 $(Package/$(1)/depends) 依赖中取出所有的依赖包名，拼接到依赖链中，得到 $(Package/$(dep0)/depends) $(dep0)
						$(sort $(foreach dep0, \
							$(Package/$(1)/depends), \
							$(Package/$(dep0)/depends) $(dep0) \
						)), \
						$(Package/$(dep1)/depends) $(dep1) \
					)), \
					$(Package/$(dep2)/depends) $(dep2) \
				)), \
				$(Package/$(dep3)/depends) $(dep3) \
			)), \
			$(Package/$(dep4)/depends) $(dep4) \
		))) \
	))

# 从当前目录路径提取包目录名
PKG_DIR_NAME:=$(lastword $(subst /,$(space),$(CURDIR)))
# 检查是否存在禁用自动重建的标记
STAMP_NO_AUTOREBUILD=$(wildcard $(PKG_BUILD_DIR)/.no_autorebuild)
# 如果禁用自动重建，查找已有的 prepared 时间戳
PREV_STAMP_PREPARED:=$(if $(STAMP_NO_AUTOREBUILD),$(wildcard $(PKG_BUILD_DIR)/.prepared*))
ifneq ($(PREV_STAMP_PREPARED),)
  STAMP_PREPARED:=$(PREV_STAMP_PREPARED)
  CONFIG_AUTOREBUILD:=
else
  # 准备阶段时间戳文件，包含MD5哈希以检测变化
  STAMP_PREPARED=$(PKG_BUILD_DIR)/.prepared$(if $(QUILT)$(DUMP),,_$(shell $(call $(if $(CONFIG_AUTOREMOVE),find_md5_reproducible,find_md5),${CURDIR} $(PKG_FILE_DEPENDS),))_$(call confvar,CONFIG_AUTOREMOVE $(PKG_PREPARED_DEPENDS)))
endif
# 配置阶段时间戳
STAMP_CONFIGURED=$(PKG_BUILD_DIR)/.configured$(if $(DUMP),,_$(call confvar,$(PKG_CONFIG_DEPENDS)))
STAMP_CONFIGURED_WILDCARD=$(PKG_BUILD_DIR)/.configured_*
# 构建阶段时间戳
STAMP_BUILT:=$(PKG_BUILD_DIR)/.built
# 安装阶段时间戳
STAMP_INSTALLED:=$(STAGING_DIR)/stamp/.$(PKG_DIR_NAME)$(if $(BUILD_VARIANT),.$(BUILD_VARIANT),)_installed

# staging 目录中的文件列表名称，用于跟踪包安装的文件
STAGING_FILES_LIST:=$(PKG_DIR_NAME)$(if $(BUILD_VARIANT),.$(BUILD_VARIANT),).list

# 清理staging函数
define CleanStaging
  # 删除安装时间戳
	rm -f $(STAMP_INSTALLED)
  # 如果存在文件列表，调用清理脚本移除已安装的文件
	@-(\
		if [ -f $(STAGING_DIR)/packages/$(STAGING_FILES_LIST) ]; then \
			$(SCRIPT_DIR)/clean-package.sh \
				"$(STAGING_DIR)/packages/$(STAGING_FILES_LIST)" \
				"$(STAGING_DIR)"; \
		fi; \
	)
endef

# 包安装时间戳
PKG_INSTALL_STAMP:=$(PKG_INFO_DIR)/$(PKG_DIR_NAME).$(if $(BUILD_VARIANT),$(BUILD_VARIANT),default).install

# Normalize package SOURCE entry to pack reproducible package
# If we are packing a package with OpenWrt buildroot:
# - Replace package/... with feeds/base/...
# If we are packing a package with SDK:
# - Replace feeds/.*_root/... with feeds/.*/... and remove
#   the intermediate directory to reflect what the symbolic link
#   points to.
#   Example:
#   Feed link: feeds/base_root/package -> feeds/base
#   Package: feeds/base_root/package/system/uci -> feeds/base/system/uci
# 标准化包的源码路径
# 处理feeds目录和package目录的路径映射,将实际路径转换为标准化的源码Makefile路径
ifeq ($(DUMP),)
  # 当前包的相对路径
  __pkg_base_path:=$(patsubst $(TOPDIR)/%,%,$(CURDIR))
  # 取第一级路径
  __pkg_provider_path:=$(word 1,$(subst /, ,$(__pkg_base_path)))
  # 如果在 feeds 目录下
  ifeq ($(__pkg_provider_path), feeds)
    # feeds/luci
    __pkg_feed_path:=$(word 2,$(subst /, ,$(__pkg_base_path)))
    __pkg_feed_name:=$(patsubst %_root,%,$(__pkg_feed_path))
    ifneq (__pkg_feed_path, __pkg_feed_name)
      __pkg_feed_realpath:=$(realpath $(TOPDIR)/feeds/$(__pkg_feed_name))
      __pkg_feed_dir:=$(patsubst $(TOPDIR)/feeds/$(__pkg_feed_path)/%,%,$(__pkg_feed_realpath))
      __pkg_path:=$(patsubst feeds/$(__pkg_feed_path)/$(__pkg_feed_dir)/%,%,$(__pkg_base_path))
    else
      __pkg_path:=$(patsubst feeds/$(__pkg_feed_path)/%,%,$(__pkg_base_path))
    endif
    __pkg_source_makefile:=$(TOPDIR)/feeds/$(__pkg_feed_name)/$(__pkg_path)
  else ifeq ($(__pkg_provider_path), package)
    __pkg_source_makefile:=$(TOPDIR)/feeds/base/$(patsubst package/%,%,$(__pkg_base_path))
  endif
endif

# 包默认设置
include $(INCLUDE_DIR)/package-defaults.mk
# 包信息导出
include $(INCLUDE_DIR)/package-dumpinfo.mk
# 打包功能
include $(INCLUDE_DIR)/package-pack.mk
# 二进制包处理
include $(INCLUDE_DIR)/package-bin.mk
# autotools支持
include $(INCLUDE_DIR)/autotools.mk

# 如果使用QUILT则为空，否则为"."
_pkg_target:=$(if $(QUILT),,.)

# 清空 MAKEFLAGS 避免干扰
override MAKEFLAGS=
# 设置配置站点文件路径
CONFIG_SITE:=$(INCLUDE_DIR)/site/$(ARCH)
CUR_MAKEFILE:=$(filter-out Makefile,$(firstword $(MAKEFILE_LIST)))
# 构造子 make 命令
SUBMAKE:=$(NO_TRACE_MAKE) $(if $(CUR_MAKEFILE),-f $(CUR_MAKEFILE))
# 设置pkg-config搜索路径
PKG_CONFIG_PATH=$(STAGING_DIR)/usr/lib/pkgconfig:$(STAGING_DIR)/usr/share/pkgconfig
unexport QUIET CONFIG_SITE

# 只在非DUMP模式且不是特殊目标时启用
ifeq ($(DUMP)$(filter prereq clean refresh update,$(MAKECMDGOALS)),)
  # 如果启用自动重建，定义自动清理规则
  ifneq ($(if $(QUILT),,$(CONFIG_AUTOREBUILD)),)
    define Build/Autoclean
      $(PKG_BUILD_DIR)/.dep_files: $(STAMP_PREPARED)
      # 使用 rdep 跟踪文件依赖关系
      $(call rdep,${CURDIR} $(PKG_FILE_DEPENDS),$(STAMP_PREPARED),$(PKG_BUILD_DIR)/.dep_files,-x "*/.dep_*")
      $(if $(filter prepare,$(MAKECMDGOALS)),,$(call rdep,$(PKG_BUILD_DIR),$(STAMP_BUILT),,-x "*/.dep_*" -x "*/ipkg*"))
    endef
  endif
endif

# 使用Git源码检出方式
ifdef USE_GIT_SRC_CHECKOUT
  define Build/Prepare/Default
  # 创建构建目录
	mkdir -p $(PKG_BUILD_DIR)
  # 链接到 git-src 目录的 .git
	ln -s $(TOPDIR)/git-src/$(PKG_NAME)/.git $(PKG_BUILD_DIR)/.git
  # 检出代码并更新子模块
	( cd $(PKG_BUILD_DIR); \
		git checkout .; \
		git submodule update --recursive; \
		git submodule foreach git config --unset core.worktree; \
		git submodule foreach git checkout .; \
	)
  endef
endif

# Git 树
ifdef USE_GIT_TREE
  define Build/Prepare/Default
	mkdir -p $(PKG_BUILD_DIR)
  # 类似上面但链接到当前目录的 git-src
	ln -s $(CURDIR)/git-src $(PKG_BUILD_DIR)/.git
	( cd $(PKG_BUILD_DIR); \
		git checkout .; \
		git submodule update --recursive; \
		git submodule foreach git config --unset core.worktree; \
		git submodule foreach git checkout .; \
	)
  endef
endif

# 使用源码目录
ifdef USE_SOURCE_DIR
  define Build/Prepare/Default
  # 删除旧的构建目录
	rm -rf $(PKG_BUILD_DIR)
  # USE_SOURCE_DIR 下没有文件，打印错误
	$(if $(wildcard $(USE_SOURCE_DIR)/*),,@echo "Error: USE_SOURCE_DIR=$(USE_SOURCE_DIR) path not found"; false)
  # 创建符号链接到源码目录
	ln -snf $(USE_SOURCE_DIR) $(PKG_BUILD_DIR)
  # 创建标记文件
	touch $(PKG_BUILD_DIR)/.source_dir
  endef
endif

# 构建导出环境
define Build/Exports/Default
  # ACLOCAL搜索路径
  $(1) : export ACLOCAL_INCLUDE=$$(foreach p,$$(wildcard $$(STAGING_DIR)/usr/share/aclocal $$(STAGING_DIR)/usr/share/aclocal-* $$(STAGING_DIR_HOSTPKG)/share/aclocal $$(STAGING_DIR_HOSTPKG)/share/aclocal-* $$(STAGING_DIR)/host/share/aclocal $$(STAGING_DIR)/host/share/aclocal-*),-I $$(p))
  # staging前缀
  $(1) : export STAGING_PREFIX=$$(STAGING_DIR)/usr
  $(1) : export PATH=$$(TARGET_PATH_PKG)
  # 配置站点
  $(1) : export CONFIG_SITE:=$$(CONFIG_SITE)
  $(1) : export PKG_CONFIG_PATH:=$$(PKG_CONFIG_PATH)
  $(1) : export PKG_CONFIG_LIBDIR:=$$(PKG_CONFIG_PATH)
  $(1) : export GIT_CEILING_DIRECTORIES:=$$(BUILD_DIR)
endef
Build/Exports=$(Build/Exports/Default)

# 定义核心构建目标
define Build/CoreTargets
  # 设置时间戳变量
  STAMP_PREPARED:=$$(STAMP_PREPARED)
  STAMP_CONFIGURED:=$$(STAMP_CONFIGURED)

  # 如果使用QUILT，包含补丁管理
  # QUILT 是管理 patch 的
  $(if $(QUILT),$(Build/Quilt))
  # 调用自动清理和默认目标
  $(call Build/Autoclean)
  $(call DefaultTargets)

  # 检查下载完整性
  $(call check_download_integrity)

  # 定义download目标
  download:
    $(foreach hook,$(Hooks/Download),
      # 执行下载钩子
      $(call $(hook))$(sep)
    )

  # 准备阶段目标
  # 设置PATH环境变量
  $(STAMP_PREPARED) : export PATH=$$(TARGET_PATH_PKG)
  $(STAMP_PREPARED): $(STAMP_PREPARED_DEPENDS)
    @-rm -rf $(PKG_BUILD_DIR)
    @mkdir -p $(PKG_BUILD_DIR)
    touch $$@_check
    # 执行准备前钩子
    $(foreach hook,$(Hooks/Prepare/Pre),$(call $(hook))$(sep))
    # 调用Build/Prepare函数
    $(Build/Prepare)
    # 执行准备后钩子
    $(foreach hook,$(Hooks/Prepare/Post),$(call $(hook))$(sep))
    touch $$@

  $(call Build/Exports,$(STAMP_CONFIGURED))
  # 配置阶段目标
  $(STAMP_CONFIGURED): $(STAMP_PREPARED) $(STAMP_CONFIGURED_DEPENDS)
    # 删除旧的配置时间戳
    rm -f $(STAMP_CONFIGURED_WILDCARD)
    # 清理staging目录
    $(CleanStaging)
    # 执行配置前钩子
    $(foreach hook,$(Hooks/Configure/Pre),$(call $(hook))$(sep))
    $(Build/Configure)
    # 执行配置后钩子
    $(foreach hook,$(Hooks/Configure/Post),$(call $(hook))$(sep))
    touch $$@

  $(call Build/Exports,$(STAMP_BUILT))
  # 构建阶段
  $(STAMP_BUILT): $(STAMP_CONFIGURED) $(STAMP_BUILT_DEPENDS)
    rm -f $$@
    touch $$@_check
    $(foreach hook,$(Hooks/Compile/Pre),$(call $(hook))$(sep))
    $(Build/Compile)
    $(foreach hook,$(Hooks/Compile/Post),$(call $(hook))$(sep))
    $(Build/Install)
    $(foreach hook,$(Hooks/Install/Post),$(call $(hook))$(sep))
    touch $$@

  $(STAMP_INSTALLED) : export PATH=$$(TARGET_PATH_PKG)
  # 安装到staging目录
  $(STAMP_INSTALLED): $(STAMP_BUILT)
    rm -rf $(TMP_DIR)/stage-$(PKG_DIR_NAME)
    mkdir -p $(TMP_DIR)/stage-$(PKG_DIR_NAME)/host $(STAGING_DIR)/packages
    $(foreach hook,$(Hooks/InstallDev/Pre),\
      $(call $(hook),$(TMP_DIR)/stage-$(PKG_DIR_NAME),$(TMP_DIR)/stage-$(PKG_DIR_NAME)/host)$(sep)\
    )
    $(call Build/InstallDev,$(TMP_DIR)/stage-$(PKG_DIR_NAME),$(TMP_DIR)/stage-$(PKG_DIR_NAME)/host)
    $(foreach hook,$(Hooks/InstallDev/Post),\
      $(call $(hook),$(TMP_DIR)/stage-$(PKG_DIR_NAME),$(TMP_DIR)/stage-$(PKG_DIR_NAME)/host)$(sep)\
    )
    # 清理旧的安装文件
    if [ -f $(STAGING_DIR)/packages/$(STAGING_FILES_LIST) ]; then \
      $(SCRIPT_DIR)/clean-package.sh \
        "$(STAGING_DIR)/packages/$(STAGING_FILES_LIST)" \
        "$(STAGING_DIR)"; \
    fi
    if [ -d $(TMP_DIR)/stage-$(PKG_DIR_NAME) ]; then \
      # 生成文件列表并写入 files 文件
      (cd $(TMP_DIR)/stage-$(PKG_DIR_NAME); find ./ > $(TMP_DIR)/stage-$(PKG_DIR_NAME).files); \
      # 复制文件到 staging 目录
      $(call locked, \
        mv $(TMP_DIR)/stage-$(PKG_DIR_NAME).files $(STAGING_DIR)/packages/$(STAGING_FILES_LIST) && \
        $(CP) $(TMP_DIR)/stage-$(PKG_DIR_NAME)/* $(STAGING_DIR)/; \
      ,staging-dir); \
    fi
    rm -rf $(TMP_DIR)/stage-$(PKG_DIR_NAME)
    touch $$@

  # 如果定义了InstallDev
  ifdef Build/InstallDev
    # compile依赖于STAMP_INSTALLED
    $(_pkg_target)compile: $(STAMP_INSTALLED)
  endif

  $(_pkg_target)prepare: $(STAMP_PREPARED)
  $(_pkg_target)configure: $(STAMP_CONFIGURED)
  $(_pkg_target)dist: $(STAMP_CONFIGURED)
  $(_pkg_target)distcheck: $(STAMP_CONFIGURED)

  # 如果启用自动移除，在编译后清理构建目录中的临时文件
  ifneq ($(CONFIG_AUTOREMOVE),)
    compile:
      -touch -r $(PKG_BUILD_DIR)/.built $(PKG_BUILD_DIR)/.autoremove 2>/dev/null >/dev/null
      $(FIND) $(PKG_BUILD_DIR) -mindepth 1 -maxdepth 1 -not '(' -type f -and -name '.*' -and -size 0 ')' -and -not -name '.pkgdir'  -print0 | \
        $(XARGS) -0 rm -rf
  endif
endef

# 默认目标定义
define Build/DefaultTargets
  # strip 用于移除字符串中所有的空格
  # 这里只是定义了目标，但是没有真正执行下载
  $(if $(PKG_SKIP_DOWNLOAD),,$(if $(strip $(PKG_SOURCE_URL)),$(call Download,default)))
  # 如果不是DUMP模式，包含核心构建目标
  $(if $(DUMP),,$(Build/CoreTargets))

  # 重新定义为空，防止重复调用
  define Build/DefaultTargets
  endef
endef

# 构建包
define BuildPackage
  # 应用默认包设置
  $(eval $(Package/Default))
  # 执行包自定义的目标，进行变量覆盖
  $(eval $(Package/$(1)))

# 检查过时的DESCRIPTION变量
ifdef DESCRIPTION
$$(error DESCRIPTION:= is obsolete, use Package/PKG_NAME/description)
endif

# 默认 description 为 title
ifndef Package/$(1)/description
define Package/$(1)/description
	$(TITLE)
endef
endif

  # 添加到构建包列表
  BUILD_PACKAGES += $(1)
  $(STAMP_PREPARED): $$(if $(QUILT)$(DUMP),,$(call find_library_dependencies,$(1)))

  # 必填校验
  $(foreach FIELD, TITLE CATEGORY SECTION VERSION,
    ifeq ($($(FIELD)),)
      $$(error Package/$(1) is missing the $(FIELD) field)
    endif
  )

  $(if $(DUMP), \
	  # 在这里执行的 Dumpinfo/Package
    $(if $(CHECK),,$(Dumpinfo/Package)), \
    $(foreach target, \
      $(if $(Package/$(1)/targets),$(Package/$(1)/targets), \
        $(if $(PKG_TARGETS),$(PKG_TARGETS), ipkg) \
      ), $(BuildTarget/$(target)) \
    ) \
  )
  # 如果不是仅主机包，调用默认目标
  $(if $(PKG_HOST_ONLY),,$(call Build/DefaultTargets,$(1)))
endef

# 安装数据文件的辅助函数
define pkg_install_files
	$(foreach install_file,$(1),$(INSTALL_DIR) $(3)/`dirname $(install_file)`; $(INSTALL_DATA) $(2)/$(install_file) $(3)/`dirname $(install_file)`;)
endef

# 安装可执行文件的辅助函数
define pkg_install_bin
	$(foreach install_apps,$(1),$(INSTALL_DIR) $(3)/`dirname $(install_apps)`; $(INSTALL_BIN) $(2)/$(install_apps) $(3)/`dirname $(install_apps)`;)
endef

Build/Prepare=$(call Build/Prepare/Default,)
Build/Configure=$(call Build/Configure/Default,)
Build/Compile=$(call Build/Compile/Default,$(if $(PKG_SUBDIRS),SUBDIRS='$$$$(wildcard $(PKG_SUBDIRS))'))
Build/Install=$(if $(PKG_INSTALL),$(call Build/Install/Default,))
Build/Dist=$(call Build/Dist/Default,)
Build/DistCheck=$(call Build/DistCheck/Default,)

# 禁用并行执行
.NOTPARALLEL:

.PHONY: prepare-package-install
prepare-package-install:
	@mkdir -p $(PKG_INFO_DIR)
	@rm -f $(PKG_INSTALL_STAMP)
	@echo "$(filter-out essential nonshared,$(PKG_FLAGS))" > $(PKG_INSTALL_STAMP).flags

$(PACKAGE_DIR):
	mkdir -p $@

compile:
.install: .compile
install: compile

force-clean-build: FORCE
	rm -rf $(PKG_BUILD_DIR)

clean-build: $(if $(wildcard $(PKG_BUILD_DIR)/.autoremove),force-clean-build)

clean: force-clean-build
	$(CleanStaging)
	$(call Build/UninstallDev,$(STAGING_DIR),$(STAGING_DIR)/host)
	$(Build/Clean)
	rm -f $(STAGING_DIR)/packages/$(STAGING_FILES_LIST)

dist:
	$(Build/Dist)

distcheck:
	$(Build/DistCheck)
