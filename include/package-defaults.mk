# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2006-2020 OpenWrt.org

# 通用包模板和默认构建流程的核心片段，给每个包提供统一的“依赖修正、Package 元信息默认值、Autotools/configure 参数、make 编译/安装命令”等

# 给普通软件包默认加上对 libc 的运行时依赖（OpenWrt 里的依赖语法里，+pkg 表示强制依赖，构建系统会自动拉取）
PKG_DEFAULT_DEPENDS = +libc

# PKG_FIXUP_DEPENDS 是个宏，会被 call
ifneq ($(PKG_NAME),toolchain)
  # 若包名匹配 kmod-%（内核模块），不附加默认依赖：返回 $(2)（原依赖）
  # 否则给依赖头部加上 $(PKG_DEFAULT_DEPENDS) 并避免重复
  PKG_FIXUP_DEPENDS = $(if $(filter kmod-%,$(1)),$(2),$(PKG_DEFAULT_DEPENDS) $(filter-out $(PKG_DEFAULT_DEPENDS),$(2)))
else
  # 若 PKG_NAME == toolchain，原样返回 $(2)（工具链元包不应该带 +libc 之类的运行时依赖）
  PKG_FIXUP_DEPENDS = $(2)
endif

# 处理一些包相关的变量信息，变量间的优先级啥的
define Package/Default
  CONFIGFILE:=
  SECTION:=opt
  CATEGORY:=Extra packages
  DEPENDS:=
  MDEPENDS:=
  CONFLICTS:=
  PROVIDES:=
  EXTRA_DEPENDS:=
  MAINTAINER:=$(PKG_MAINTAINER)
  # $(patsubst pattern,replacement,text) 用于在 text 中匹配 pattern，并替换为 replacement
  # 后面一个 patsubst 先检查当前包所在路径是不是以 $(TOPDIR)/package/ 开头的，如果是则替换为 feeds/base/ 开头的
  # 前面这个 patsubst 则是转为相对于 TOPDIR 的相对路径
  # SOURCE:=$(patsubst $(TOPDIR)/%,%,$(patsubst $(TOPDIR)/package/%,feeds/base/%,$(CURDIR)))
  # 指向该包 Makefile 的相对路径（用于溯源/调试）
  SOURCE:=$(patsubst $(TOPDIR)/%,%,$(if $(__pkg_source_makefile),$(__pkg_source_makefile),$(CURDIR)))
  ifneq ($(PKG_VERSION),)
    ifneq ($(PKG_RELEASE),)
      VERSION:=$(PKG_VERSION)-r$(PKG_RELEASE)
    else
      VERSION:=$(PKG_VERSION)
    endif
  else
    VERSION:=$(PKG_RELEASE)
  endif
  ABI_VERSION:=
  ifneq ($(PKG_FLAGS),)
    PKGFLAGS:=$(PKG_FLAGS)
  else
    PKGFLAGS:=
  endif
  ifneq ($(ARCH_PACKAGES),)
    PKGARCH:=$(ARCH_PACKAGES)
  else
    PKGARCH:=$(BOARD)
  endif
  DEFAULT:=
  MENU:=
  SUBMENU:=
  SUBMENUDEP:=
  TITLE:=
  KCONFIG:=
  BUILDONLY:=
  HIDDEN:=
  URL:=$(PKG_URL)
  VARIANT:=
  DEFAULT_VARIANT:=
  USERID:=
  ALTERNATIVES:=
  LICENSE:=$(PKG_LICENSE)
  LICENSE_FILES:=$(PKG_LICENSE_FILES)
  FILE_MODES:=$(PKG_FILE_MODES)
endef

Build/Patch:=$(Build/Patch/Default)
# 如果定义了 PKG_UNPACK（通常是解 tarball 的命令），则提供 Build/Prepare/Default：
ifneq ($(strip $(PKG_UNPACK)),)
  define Build/Prepare/Default
	$(PKG_UNPACK)
	# 复制本地 ./src/ 到 $(PKG_BUILD_DIR)（覆盖源码/打补丁的另一种方式）
	[ ! -d ./src/ ] || $(CP) ./src/. $(PKG_BUILD_DIR)
	# 调用 $(Build/Patch)（应用补丁集）
	$(Build/Patch)
  endef
endif

EXTRA_CXXFLAGS = $(EXTRA_CFLAGS)
ifeq ($(CONFIG_BUILD_NLS),y)
	# 表示开启本地化
    DISABLE_NLS:=
else
	# 禁用本地化
    DISABLE_NLS:=--disable-nls
endif

# 配合 OpenWrt 的前缀布局（并非宿主机 /usr，而是目标 rootfs 的 /usr）
CONFIGURE_PREFIX:=/usr
# Autoconf 配置
CONFIGURE_ARGS = \
		# 确保交叉编译正确识别“构建机/宿主/目标”三元组
		--target=$(GNU_TARGET_NAME) \
		--host=$(GNU_TARGET_NAME) \
		--build=$(GNU_HOST_NAME) \
		--disable-dependency-tracking \
		--program-prefix="" \
		--program-suffix="" \
		--prefix=$(CONFIGURE_PREFIX) \
		--exec-prefix=$(CONFIGURE_PREFIX) \
		--bindir=$(CONFIGURE_PREFIX)/bin \
		--sbindir=$(CONFIGURE_PREFIX)/sbin \
		--libexecdir=$(CONFIGURE_PREFIX)/lib \
		--sysconfdir=/etc \
		--datadir=$(CONFIGURE_PREFIX)/share \
		--localstatedir=/var \
		--mandir=$(CONFIGURE_PREFIX)/man \
		--infodir=$(CONFIGURE_PREFIX)/info \
		$(DISABLE_NLS) \
		$(DISABLE_IPV6)

# 传递给 ./configure 的环境变量
CONFIGURE_VARS = \
		# 提供 CC/CXX/LD/AR/AS/NM/STRIP、STAGING_DIR、SYSROOT 等关键交叉编译变量
		$(TARGET_CONFIGURE_OPTS) \
		CFLAGS="$(TARGET_CFLAGS) $(EXTRA_CFLAGS)" \
		CXXFLAGS="$(TARGET_CXXFLAGS) $(EXTRA_CXXFLAGS)" \
		CPPFLAGS="$(TARGET_CPPFLAGS) $(EXTRA_CPPFLAGS)" \
		LDFLAGS="$(TARGET_LDFLAGS) $(EXTRA_LDFLAGS)" \

# configure 所在路径与命令名（可被包覆写）
CONFIGURE_PATH = .
CONFIGURE_CMD = ./configure

# 替换源码树中的 config.guess / config.sub 为较新版本，保证识别新架构（如 musl/新 CPU 三元组）。
# 先 chmod u+w 解除只读，再 cp --remove-destination 覆盖
replace_script=$(FIND) $(1) -name $(2) | $(XARGS) chmod u+w; \
	       $(FIND) $(1) -name $(2) | $(XARGS) -n1 cp --remove-destination \
	       $(SCRIPT_DIR)/$(2);

# $(1)：附加的 configure 选项
# $(2)：在执行 ./configure 之前追加的命令/环境片段
# $(3)：额外的相对子路径，支持在源码的某个子目录里运行 ./configure
define Build/Configure/Default
	(cd $(PKG_BUILD_DIR)/$(CONFIGURE_PATH)/$(strip $(3)); \
	# 存在可执行的 configure
	if [ -x $(CONFIGURE_CMD) ]; then \
		# 更新 config.guess/sub
		$(call replace_script,$(PKG_BUILD_DIR)/$(3),config.guess) \
		$(call replace_script,$(PKG_BUILD_DIR)/$(3),config.sub) \
		$(CONFIGURE_VARS) \
		# 包传入额外 configure 参数
		$(2) \
		$(CONFIGURE_CMD) \
		$(CONFIGURE_ARGS) \
		$(1); \
	fi; \
	)
endef

# 为 make 传递编译/链接选项
# 这里把 CPPFLAGS 也拼进 CFLAGS/CXXFLAGS，兼容某些上游 Makefile
MAKE_VARS = \
	CFLAGS="$(TARGET_CFLAGS) $(EXTRA_CFLAGS) $(TARGET_CPPFLAGS) $(EXTRA_CPPFLAGS)" \
	CXXFLAGS="$(TARGET_CXXFLAGS) $(EXTRA_CXXFLAGS) $(TARGET_CPPFLAGS) $(EXTRA_CPPFLAGS)" \
	LDFLAGS="$(TARGET_LDFLAGS) $(EXTRA_LDFLAGS)"

# 很多上游 Makefile 使用 CROSS 和 ARCH 这两项来决定交叉前缀与架构。
MAKE_FLAGS = \
	$(TARGET_CONFIGURE_OPTS) \
	CROSS="$(TARGET_CROSS)" \
	ARCH="$(ARCH)"

MAKE_INSTALL_FLAGS = \
	$(MAKE_FLAGS) \
	# 约定安装到临时根 $(PKG_INSTALL_DIR)，后续再从这里打包成 ipk
	DESTDIR="$(PKG_INSTALL_DIR)"

# 默认在构建目录根执行 make
MAKE_PATH ?= .

define Build/Compile/Default
	+$(MAKE_VARS) \
	$(MAKE) $(PKG_JOBS) -C $(PKG_BUILD_DIR)/$(MAKE_PATH) \
		$(MAKE_FLAGS) \
		$(1);
endef

# $1 make 执行的目标
define Build/Install/Default
	$(MAKE_VARS) \
	$(MAKE) -C $(PKG_BUILD_DIR)/$(MAKE_PATH) \
		$(MAKE_INSTALL_FLAGS) \
		# 一些上游项目需要指定 SUBDIRS 才会递归安装子目录
		# 最终 shell 接收到的是形如 SUBDIRS='dir1 dir2' 的字面值
		$(if $(PKG_SUBDIRS),SUBDIRS='$$$$(wildcard $(PKG_SUBDIRS))') \
		# 默认执行 install 目标
		$(if $(1), $(1), install);
endef

define Build/Dist/Default
	$(call Build/Compile/Default, DESTDIR="$(PKG_BUILD_DIR)/tmp" CC="$(TARGET_CC)" dist)
endef

define Build/DistCheck/Default
	$(call Build/Compile/Default, DESTDIR="$(PKG_BUILD_DIR)/tmp" CC="$(TARGET_CC)" distcheck)
endef
