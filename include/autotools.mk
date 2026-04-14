# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2007-2020 OpenWrt.org

# 提供“自动执行 autoreconf / libtool 打补丁 / gettext 版本同步”等通用宏，并通过 Hooks 机制在 Configure 阶段前后挂接

ifneq ($(__autotools_inc),1)
__autotools_inc=1

# 把布尔配置变量转成 --enable-xxx/--disable-xxx 选项
autoconf_bool = $(patsubst %,$(if $($(1)),--enable,--disable)-%,$(2))

# 从某目录删除所有 .la 文件（避免 libtool 旧链式依赖问题）
# delete *.la-files from staging_dir - we can not yet remove respective lines within all package
# Makefiles, since backfire still uses libtool v1.5.x which (may) require those files
define libtool_remove_files
	find $(1) -name '*.la' | $(XARGS) rm -f;
endef

# 为 autoreconf 定位 host 端的 autoconf/automake/libtoolize 等工具
AM_TOOL_PATHS:= \
	AUTOM4TE=$(STAGING_DIR_HOST)/bin/autom4te \
	AUTOCONF=$(STAGING_DIR_HOST)/bin/autoconf \
	AUTOMAKE=$(STAGING_DIR_HOST)/bin/automake \
	ACLOCAL=$(STAGING_DIR_HOST)/bin/aclocal \
	AUTOHEADER=$(STAGING_DIR_HOST)/bin/autoheader \
	LIBTOOLIZE=$(STAGING_DIR_HOST)/bin/libtoolize \
	LIBTOOL=$(STAGING_DIR_HOST)/bin/libtool \
	M4=$(STAGING_DIR_HOST)/bin/m4 \
	AUTOPOINT=true \
	GTKDOCIZE=true

AM_TOOL_PATHS_FAKE:=$(subst = ,=,$(patsubst "%,"$(TRUE)",$(subst =,= ",$(AM_TOOL_PATHS))))

# 1: build dir，构建目录
# 2: remove files，在执行前要删除的文件列表，如 aclocal.m4
# 3: automake paths，包含 configure.ac/in 的目录集合；会 foreach 遍历逐个 autoreconf
# 4: libtool paths，附加为 -I 的路径，通常为放置 libtool.m4 的目录
# 5: extra m4 dirs，附加为 -I 的路径，额外的 m4 宏目录
define autoreconf
	(cd $(1); \
		# 在 $2 前面拼接 rm -f ，用于删除
		$(patsubst %,rm -f %;,$(2)) \
		# 遍历 $(3) 中的每个路径
		$(foreach p,$(3), \
			# 如果存在 configure.ac/in
			if [ -f $(p)/configure.ac ] || [ -f $(p)/configure.in ]; then \
				# 清理 autom4te.cache
				[ -d $(p)/autom4te.cache ] && rm -rf $(p)/autom4te.cache; \
				# 如果没有 config.rpath，链接脚本下的通用版到当前目录下
				[ -e $(p)/config.rpath ] || \
						ln -s $(SCRIPT_DIR)/config.rpath $(p)/config.rpath; \
				# 兼容 automake/autoreconf 的“GNU 模式”检查。很多上游的 configure.ac/Makefile.am 默认 AM_INIT_AUTOMAKE 处于 gnu 严格模式（未写 foreign），automake 在生成 Makefile.in 时会强制要求若干“标准文档文件”存在
				# 如果缺少这些文件，autoreconf/automake 会直接报错中止
				touch NEWS AUTHORS COPYING ABOUT-NLS ChangeLog; \
				$(AM_TOOL_PATHS) \
					LIBTOOLIZE='$(STAGING_DIR_HOST)/bin/libtoolize --install' \
					$(STAGING_DIR_HOST)/bin/autoreconf -v -f -i \
					$(if $(word 2,$(3)),--no-recursive) \
					# 默认 aclocal 搜索路径
					-B $(STAGING_DIR_HOST)/share/aclocal \
					$(patsubst %,-I %,$(5)) \
					$(patsubst %,-I %,$(4)) $(p) || true; \
			fi; \
		) \
	);
endef

# 在 $(1) 下寻找 ltmain.sh，读取其 VERSION，若为 1.5/2.2/2.4 则应用对应补丁 tools/libtool/files/libtool-vX.Y.patch；否则报不支持
# libtool-vX.Y.patch 是 OpenWrt 在交叉编译场景下对上游自带 libtool 脚本（ltmain.sh）的一组定制补丁。它的目的不是“修功能”，而是“改行为”，让使用 libtool 的上游项目在 OpenWrt 的交叉环境里构建时不会把错误的路径/依赖写进产物，也不会在安装阶段做不可行的“重链接”。
# 它通常做了这些事情（不同版本细节略有差异，但目标一致）：
# 1. 禁止或削弱 RPATH/硬编码路径
# 	避免把构建时的 $(STAGING_DIR)/usr/lib 等绝对路径写进 .so 的 RUNPATH/RPATH。
# 	防止把 host/staging 的路径写进 .la 的 dependency_libs，减少“直接链接间接依赖”的污染。
# 	原因：这些路径在目标机上不存在，会导致运行失败或不必要的依赖拉入。
# 2. 关闭/绕过 install 阶段的 relink
# 	libtool 默认在 “make install” 时对 libtool 构建的库可执行进行一次 “relink”，实际是使用最终安装路径重跑链接。
# 	在交叉编译环境无法在目标机运行/解析，且会错误解析路径；补丁会跳过或中和该步骤。
# 	典型症状：不打补丁会看到 “libtool: relink ...” 相关失败。
# 3. 针对交叉编译/sysroot 的路径处理修正
# 	让链接时更好地遵守 sysroot 语义，避免非 sysroot 路径优先。
# 	处理 -L/path 与 -rpath 的匹配，防止把 staging 的 -L 转为最终 rpath。
# 	对 Linux 下的“不要硬编码 rpath 到 /usr/lib”策略做适配。
# 4. 降低 .la 文件副作用
# 	即便我们后续会删除 .la（libtool_remove_files），构建时仍可能读写它们。
# 	补丁会减少/过滤 dependency_libs 的写入，弱化对 .la 的连带依赖，降低“链式直连”的副作用（例如强制链接到一长串间接库）。
# 5. 兼容旧版 libtool 的已知问题
# 	1.5、2.2、2.4 系列对 Linux/交叉环境存在不同程度的历史问题，OpenWrt 做了针对性改动以统一构建行为。
# 	如果检测到非支持版本，会报错（脚本里 case 只列出 1.5/2.2/2.4）

# 为什么在 ltmain.sh 打补丁而不是只跑 autoreconf
# 	许多上游发布包自带了生成好的 libtool/ltmain.sh，且不会在构建时重跑 libtoolize；单跑 autoreconf 未必会替换这些文件或引入我们需要的行为。
# 	直接 patch ltmain.sh 可以确保即使不 autoreconf，也能得到期望的链接行为；而 PKG_FIXUP:=libtool 的逻辑会自动拉起 autoreconf 以补齐宏（除非指定 no-autoreconf）。
# 1: build dir
define patch_libtool
	@(cd $(1); \
		for lt in $$$$($$(STAGING_DIR_HOST)/bin/find . -name ltmain.sh); do \
			lt_version="$$$$($$(STAGING_DIR_HOST)/bin/sed -ne 's,^[[:space:]]*VERSION="\?\([0-9]\.[0-9]\+\).*,\1,p' $$$$lt)"; \
			case "$$$$lt_version" in \
				1.5|2.2|2.4) echo "autotools.mk: Found libtool v$$$$lt_version - applying patch to $$$$lt"; \
					(cd $$$$(dirname $$$$lt) && $$(PATCH) -N -s -p1 < $$(TOPDIR)/tools/libtool/files/libtool-v$$$$lt_version.patch || true) ;; \
				*) echo "autotools.mk: error: Unsupported libtool version v$$$$lt_version - cannot patch $$$$lt"; exit 1 ;; \
			esac; \
		done; \
	);
endef

define set_libtool_abiver
	sed -i \
		-e 's,^soname_spec=.*,soname_spec="\\$$$${libname}\\$$$${shared_ext}.$(PKG_ABI_VERSION)",' \
		-e 's,^library_names_spec=.*,library_names_spec="\\$$$${libname}\\$$$${shared_ext}.$(PKG_ABI_VERSION) \\$$$${libname}\\$$$${shared_ext}",' \
		$(PKG_BUILD_DIR)/libtool
endef

PKG_LIBTOOL_PATHS?=$(CONFIGURE_PATH)
PKG_AUTOMAKE_PATHS?=$(CONFIGURE_PATH)
PKG_MACRO_PATHS?=m4
PKG_REMOVE_FILES?=aclocal.m4

Hooks/InstallDev/Post += libtool_remove_files

# autoreconf 的进一步封装
define autoreconf_target
  $(strip $(call autoreconf, \
    $(PKG_BUILD_DIR), $(PKG_REMOVE_FILES), \
    $(PKG_AUTOMAKE_PATHS), $(PKG_LIBTOOL_PATHS), \
    $(STAGING_DIR)/host/share/aclocal $(STAGING_DIR_HOSTPKG)/share/aclocal $(STAGING_DIR)/usr/share/aclocal $(PKG_MACRO_PATHS)))
endef

define patch_libtool_target
  $(strip $(call patch_libtool, \
    $(PKG_BUILD_DIR)))
endef

# 读取 host 上 gettext 版本，用 sed 把 $(PKG_BUILD_DIR)/configure.ac 里的 AM_GNU_GETTEXT_VERSION(...) 替换为当前版本，再执行 autopoint --force
define gettext_version_target
	(cd $(PKG_BUILD_DIR) && \
		GETTEXT_VERSION=$(shell $(STAGING_DIR_HOSTPKG)/bin/gettext -V | $(STAGING_DIR_HOST)/bin/sed -rne '1s/.*\b([0-9]\.[0-9]+(\.[0-9]+)?)\b.*/\1/p' ) && \
		$(STAGING_DIR_HOST)/bin/sed \
			-i $(PKG_BUILD_DIR)/configure.ac \
			-e "s/AM_GNU_GETTEXT_VERSION(.*)/AM_GNU_GETTEXT_VERSION(\[$$$$GETTEXT_VERSION\])/g" && \
		$(STAGING_DIR_HOSTPKG)/bin/autopoint --force \
	);
endef

# 通过给 PKG_FIXUP 增加标志，可把对应动作挂到 Hooks
ifneq ($(filter gettext-version,$(PKG_FIXUP)),)
  Hooks/Configure/Pre += gettext_version_target
 ifeq ($(filter no-autoreconf,$(PKG_FIXUP)),)
  Hooks/Configure/Pre += autoreconf_target
 endif
endif

ifneq ($(filter patch-libtool,$(PKG_FIXUP)),)
  Hooks/Configure/Pre += patch_libtool_target
endif

ifneq ($(filter libtool,$(PKG_FIXUP)),)
  PKG_BUILD_DEPENDS += libtool
 ifeq ($(filter no-autoreconf,$(PKG_FIXUP)),)
  Hooks/Configure/Pre += autoreconf_target
 endif
endif

ifneq ($(filter libtool-abiver,$(PKG_FIXUP)),)
  Hooks/Configure/Post += set_libtool_abiver
endif

ifneq ($(filter autoreconf,$(PKG_FIXUP)),)
  ifeq ($(filter autoreconf,$(Hooks/Configure/Pre)),)
    Hooks/Configure/Pre += autoreconf_target
  endif
endif


HOST_FIXUP?=$(PKG_FIXUP)
HOST_LIBTOOL_PATHS?=$(if $(PKG_LIBTOOL_PATHS),$(PKG_LIBTOOL_PATHS),.)
HOST_AUTOMAKE_PATHS?=$(if $(PKG_AUTOMAKE_PATHS),$(PKG_AUTOMAKE_PATHS),.)
HOST_MACRO_PATHS?=$(if $(PKG_MACRO_PATHS),$(PKG_MACRO_PATHS),m4)
HOST_REMOVE_FILES?=$(PKG_REMOVE_FILES)

define autoreconf_host
  $(strip $(call autoreconf, \
    $(HOST_BUILD_DIR), $(HOST_REMOVE_FILES), \
    $(HOST_AUTOMAKE_PATHS), $(HOST_LIBTOOL_PATHS), \
    $(HOST_MACRO_PATHS)))
endef

define patch_libtool_host
  $(strip $(call patch_libtool, \
    $(HOST_BUILD_DIR)))
endef

ifneq ($(filter patch-libtool,$(HOST_FIXUP)),)
  Hooks/HostConfigure/Pre += patch_libtool_host
endif

ifneq ($(filter libtool,$(HOST_FIXUP)),)
 ifeq ($(filter no-autoreconf,$(HOST_FIXUP)),)
  Hooks/HostConfigure/Pre += autoreconf_host
 endif
endif

ifneq ($(filter autoreconf,$(HOST_FIXUP)),)
  ifeq ($(filter autoreconf,$(Hooks/HostConfigure/Pre)),)
    Hooks/HostConfigure/Pre += autoreconf_host
  endif
endif

endif #__autotools_inc
