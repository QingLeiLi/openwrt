# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2007-2020 OpenWrt.org

PREP_MK= OPENWRT_BUILD= QUIET=0

# MAKE_TERMOUT 是make的内置变量，标识当前是否是终端环境
export IS_TTY=$(if $(MAKE_TERMOUT),1,0)

include $(TOPDIR)/include/verbose.mk

ifeq ($(SDK),1)
  include $(TOPDIR)/include/version.mk
else
  # 获取版本号
  REVISION:=$(shell $(TOPDIR)/scripts/getver.sh)
  SOURCE_DATE_EPOCH:=$(shell $(TOPDIR)/scripts/get_source_date_epoch.sh)
endif

export REVISION
export SOURCE_DATE_EPOCH
export GIT_CONFIG_PARAMETERS='core.autocrlf=false'
export GIT_ASKPASS:=/bin/true
# MAKEFLAGS 是内置变量，指示make的参数
export MAKE_JOBSERVER=$(filter --jobserver%,$(MAKEFLAGS))
export GNU_HOST_NAME:=$(shell $(TOPDIR)/scripts/config.guess)
export HOST_OS:=$(shell uname)
export HOST_ARCH:=$(shell uname -m)

ifeq ($(HOST_OS),Darwin)
  # 不支持mac自带的make
  ifneq ($(filter /Applications/Xcode.app/% /Library/Developer/%,$(MAKE)),)
	# 打印异常信息
    $(error Please use a newer version of GNU make. The version shipped by Apple is not supported)
  endif
endif

# Perforce 版本控制使用的环境变量
# prevent perforce from messing with the patch utility
unexport P4PORT P4USER P4CONFIG P4CLIENT

# Quilt 是一个用于管理补丁集的工具
# prevent user defaults for quilt from interfering
unexport QUILT_PATCHES QUILT_PATCH_OPTS

unexport C_INCLUDE_PATH CROSS_COMPILE ARCH

# prevent distro default LPATH from interfering
unexport LPATH

# make sure that a predefined CFLAGS variable does not disturb packages
export CFLAGS=
export LDFLAGS=

empty:=
space:= $(empty) $(empty)
# 将 PATH中的 : 都替换为 空格
path:=$(subst :,$(space),$(PATH))
# 删掉所有以 . 开头的路径
path:=$(filter-out .%,$(path))
# 替换回去，可能是因为 filter-out 用空格区分多条，所以转换了一下
# 最终效果就是，path中以 . 开头的路径都被干掉了
path:=$(subst $(space),:,$(path))
export ORIG_PATH:=$(if $(ORIG_PATH),$(ORIG_PATH),$(PATH))
export PATH:=$(path)
export STAGING_DIR_HOST:=$(if $(STAGING_DIR),$(abspath $(STAGING_DIR)/../host),$(TOPDIR)/staging_dir/host)

unexport TAR_OPTIONS

ifeq ($(FORCE),)
  # 声明 这三个目标都依赖 .prereq-build
  .config scripts/config/conf scripts/config/mconf: $(STAGING_DIR_HOST)/.prereq-build
endif

# $$ 表示一个$字符串，因为有转义
# echo 收到的是 $$，在shell里面 $$ 表示当前进程的PID
# ?= 表示如果没有定义，则赋值
SCAN_COOKIE?=$(shell echo $$$$)
export SCAN_COOKIE

# umask是linux命令，用来设置新创建文件/目录的默认权限
SUBMAKE:=umask 022; $(SUBMAKE)

# _limit 存储了系统的文件描述符限制
# -o 是逻辑运算符，OR 或的意思
# 检查 ulimit，如果是 unlimited 或 超过 1024，则不做任何操作
# 否则，将 ulimit 设置为 1024
# ulimit代表了进程可打开的最大文件描述符数
ULIMIT_FIX=_limit=`ulimit -n`; [ "$$_limit" = "unlimited" -o "$$_limit" -ge 1024 ] || ulimit -n 1024;

# $(STAGING_DIR_HOST)/.prereq-build 不是个文件，他是个目标名，在下面 215 行定义的
prepare-mk: $(STAGING_DIR_HOST)/.prereq-build FORCE ;

ifdef SDK
  IGNORE_PACKAGES = linux
endif

# 遍历 IGNORE_PACKAGES，生成 --ignore 参数
_ignore = $(foreach p,$(IGNORE_PACKAGES),--ignore $(p))

# 检查 .config 文件中的 CONFIG_USE_APK CONFIG_SELINUX CONFIG_SMALL_FLASH CONFIG_SECCOMP 这几个配置是否发生变化
# 如果发生变化，删除 tmp/info/.targetinfo*，并将新的配置存到 tmp/.packagedynamicdefault
# Config that will invalidate the .targetinfo as they will affect
# DEFAULT_PACKAGES.
# 如果以下几个配置发生了变化，则清除 targetinfo 的缓存
# Keep DYNAMIC_DEF_PKG_CONF in sync with target.mk to reflect the same configs
DYNAMIC_DEF_PKG_CONF := CONFIG_USE_APK CONFIG_SELINUX CONFIG_SMALL_FLASH CONFIG_SECCOMP
check-dynamic-def-pkg: FORCE
	@+DEF_PKG_CONFS=""; \
	if [ -f $(TOPDIR)/.config ]; then \
		for config in $(DYNAMIC_DEF_PKG_CONF); do \
			# 使用 grep 命令查找配置项在 .config 文件中设置为 y 的行，并将其添加到 DEF_PKG_CONFS
			DEF_PKG_CONFS="$$DEF_PKG_CONFS "$$(grep "$$config"=y $(TOPDIR)/.config); \
		done; \
	fi; \
	# 读取旧的配置
	[ ! -f tmp/.packagedynamicdefault ] || OLD_DEF_PKG_CONFS=$$(cat tmp/.packagedynamicdefault); \
	# 新旧配置如果不同，删除 tmp/info/.targetinfo*
	[ "$$DEF_PKG_CONFS" = "$$OLD_DEF_PKG_CONFS" ] || rm -rf tmp/info/.targetinfo*; \
	mkdir -p tmp && echo "$$DEF_PKG_CONFS" > tmp/.packagedynamicdefault;

prepare-tmpinfo: check-dynamic-def-pkg FORCE
	# 检查环境要求、链接 stage/bin 所需命令
	@+$(MAKE) -r -s $(STAGING_DIR_HOST)/.prereq-build $(PREP_MK)
	mkdir -p tmp/info feeds
	# 检查 $(TOPDIR)/feeds/base 是否存在，不存在就从 $(TOPDIR)/feeds/base 链接过来
	[ -e $(TOPDIR)/feeds/base ] || ln -sf $(TOPDIR)/package $(TOPDIR)/feeds/base
	# 扫描op自身仓库里面的包,这俩命令都没有声明 TMP_DIR，缓存文件都写到顶层的 tmp 文件夹下了
	$(_SINGLE)$(NO_TRACE_MAKE) -j1 -r -s -f include/scan.mk SCAN_TARGET="packageinfo" SCAN_DIR="package" SCAN_NAME="package" SCAN_DEPTH=5 SCAN_EXTRA=""
	$(_SINGLE)$(NO_TRACE_MAKE) -j1 -r -s -f include/scan.mk SCAN_TARGET="targetinfo" SCAN_DIR="target/linux" SCAN_NAME="target" SCAN_DEPTH=3 SCAN_EXTRA="" SCAN_MAKEOPTS="TARGET_BUILD=1"
	for type in package target; do \
		f=tmp/.$${type}info; t=tmp/.config-$${type}.in; \
		# -nt 比较两个文件的修改时间
		# config 文件是通过 info 构建出来的，如果 info 比 config 新，则需要重新生成
		[ "$$t" -nt "$$f" ] || ./scripts/$${type}-metadata.pl $(_ignore) config "$$f" > "$$t" || { rm -f "$$t"; echo "Failed to build $$t"; false; break; }; \
	done
	# 将 feeds 的基本信息写到 tmp/.config-feeds.in
	[ tmp/.config-feeds.in -nt tmp/.packageauxvars ] || ./scripts/feeds feed_config > tmp/.config-feeds.in
	./scripts/package-metadata.pl mk tmp/.packageinfo > tmp/.packagedeps || { rm -f tmp/.packagedeps; false; }
	./scripts/package-metadata.pl pkgaux tmp/.packageinfo > tmp/.packageauxvars || { rm -f tmp/.packageauxvars; false; }
	./scripts/package-metadata.pl usergroup tmp/.packageinfo > tmp/.packageusergroup || { rm -f tmp/.packageusergroup; false; }
	touch $(TOPDIR)/tmp/.build

# 生成 .config 文件
.config: ./scripts/config/conf $(if $(CONFIG_HAVE_DOT_CONFIG),,prepare-tmpinfo)
	@+if [ \! -e .config ] || ! grep CONFIG_HAVE_DOT_CONFIG .config >/dev/null; then \
		[ -e $(HOME)/.openwrt/defconfig ] && cp $(HOME)/.openwrt/defconfig .config; \
		$(_SINGLE)$(NO_TRACE_MAKE) menuconfig $(PREP_MK); \
	fi

ifeq ($(RECURSIVE_DEP_IS_ERROR),1)
  KCONF_FLAGS=--fatalrecursive
endif
ifneq ($(DISTRO_PKG_CONFIG),)
# 环境变量导出，目标执行是会设置PATH，这并不是实际的目标定义，而是追加一些参数
scripts/config/%onf: export PATH:=$(dir $(DISTRO_PKG_CONFIG)):$(PATH)
endif
# 变量追加，跟上面的 export 比较类似
scripts/config/%onf: CFLAGS+= -O2
scripts/config/%onf: FORCE
	@$(_SINGLE)$(SUBMAKE) $(if $(findstring s,$(OPENWRT_VERBOSE)),,-s) \
		-C scripts/config $(notdir $@)

# 定义了 scripts/config/mconf 和 scripts/config/mconf_check 两个目标
# scripts/config/mconf_check 是为了缓存 scripts/config/mconf 的构建结果
$(eval $(call rdep,scripts/config,scripts/config/mconf))

config: scripts/config/conf prepare-tmpinfo FORCE
	[ -L .config ] && export KCONFIG_OVERWRITECONFIG=1; \
		$< $(KCONF_FLAGS) Config.in

config-clean: FORCE
	$(_SINGLE)$(NO_TRACE_MAKE) -C scripts/config clean

defconfig: scripts/config/conf prepare-tmpinfo FORCE
	touch .config
	@if [ ! -s .config -a -e $(HOME)/.openwrt/defconfig ]; then cp $(HOME)/.openwrt/defconfig .config; fi
	[ -L .config ] && export KCONFIG_OVERWRITECONFIG=1; \
		$< $(KCONF_FLAGS) --defconfig=.config Config.in

confdefault-y=allyes
confdefault-m=allmod
confdefault-n=allno
confdefault:=$(confdefault-$(CONFDEFAULT))

oldconfig: scripts/config/conf prepare-tmpinfo FORCE
	[ -L .config ] && export KCONFIG_OVERWRITECONFIG=1; \
		$< $(KCONF_FLAGS) --$(if $(confdefault),$(confdefault),old)config Config.in

menuconfig: scripts/config/mconf prepare-tmpinfo FORCE
	if [ \! -e .config -a -e $(HOME)/.openwrt/defconfig ]; then \
		cp $(HOME)/.openwrt/defconfig .config; \
	fi
	# 检查 .config 是否是个符号链接
	[ -L .config ] && export KCONFIG_OVERWRITECONFIG=1; \
		# 将 Config.in 作为参数执行 第一个依赖
		$< Config.in

nconfig: scripts/config/nconf prepare-tmpinfo FORCE
	if [ \! -e .config -a -e $(HOME)/.openwrt/defconfig ]; then \
		cp $(HOME)/.openwrt/defconfig .config; \
	fi
	[ -L .config ] && export KCONFIG_OVERWRITECONFIG=1; \
		$< Config.in

xconfig: scripts/config/qconf prepare-tmpinfo FORCE
	if [ \! -e .config -a -e $(HOME)/.openwrt/defconfig ]; then \
		cp $(HOME)/.openwrt/defconfig .config; \
	fi
	$< Config.in

prepare_kernel_conf: .config toolchain/install FORCE

# 如果这个文件不存在，定义编译 quilt 的目标
ifeq ($(wildcard $(STAGING_DIR_HOST)/bin/quilt),)
  prepare_kernel_conf:
	@+$(SUBMAKE) -r tools/quilt/compile
else
  prepare_kernel_conf: ;
endif

kernel_oldconfig: prepare_kernel_conf
	$(_SINGLE)$(NO_TRACE_MAKE) -C target/linux oldconfig

ifneq ($(DISTRO_PKG_CONFIG),)
kernel_menuconfig: export PATH:=$(dir $(DISTRO_PKG_CONFIG)):$(PATH)
kernel_nconfig: export PATH:=$(dir $(DISTRO_PKG_CONFIG)):$(PATH)
kernel_xconfig: export PATH:=$(dir $(DISTRO_PKG_CONFIG)):$(PATH)
endif
kernel_menuconfig: prepare_kernel_conf
	$(_SINGLE)$(NO_TRACE_MAKE) -C target/linux menuconfig

kernel_nconfig: prepare_kernel_conf
	$(_SINGLE)$(NO_TRACE_MAKE) -C target/linux nconfig

kernel_xconfig: prepare_kernel_conf
	$(_SINGLE)$(NO_TRACE_MAKE) -C target/linux xconfig

$(STAGING_DIR_HOST)/.prereq-build: include/prereq-build.mk
	mkdir -p tmp
	# 检查了很多环境要求、链接一些库到 $(STAGING_DIR_HOST)/bin 下面
	@$(_SINGLE)$(NO_TRACE_MAKE) -j1 -r -s -f $(TOPDIR)/include/prereq-build.mk prereq 2>/dev/null || { \
		echo "Prerequisite check failed. Use FORCE=1 to override."; \
		false; \
	}
	# 这应该是留的 hook，如果你需要额外的 prepare 步骤，建一个 makefile 去指定就可以了，不需要改主流程
	# 检查文件是否存在，貌似不存在
  ifneq ($(realpath $(TOPDIR)/include/prepare.mk),)
	@$(_SINGLE)$(NO_TRACE_MAKE) -j1 -r -s -f $(TOPDIR)/include/prepare.mk prepare 2>/dev/null || { \
		echo "Preparation failed."; \
		false; \
	}
  endif
	# 创建目标文件，结合实现 make 缓存
	touch $@

printdb: FORCE
	@$(_SINGLE)$(NO_TRACE_MAKE) -p $@ V=99 DUMP_TARGET_DB=1 2>&1

ifndef SDK
  DOWNLOAD_DIRS = tools/download toolchain/download package/download target/download
else
  DOWNLOAD_DIRS = package/download
endif

# 后面那个 flock 是没有就依赖它，促使make去把 flock 编译出来
download: .config FORCE $(if $(wildcard $(STAGING_DIR_HOST)/bin/flock),,tools/flock/compile)
	@+$(foreach dir,$(DOWNLOAD_DIRS),$(SUBMAKE) $(dir);)

clean dirclean: .config
	@+$(SUBMAKE) -r $@

prereq:: prepare-tmpinfo .config
	@+$(NO_TRACE_MAKE) -r -s $@

check: .config FORCE
	@+$(NO_TRACE_MAKE) -r -s $@ QUIET= V=s

val.% var.%: FORCE
	@+$(NO_TRACE_MAKE) -r -s $@ QUIET= V=s

WARN_PARALLEL_ERROR = $(if $(BUILD_LOG),,$(and $(filter -j,$(MAKEFLAGS)),$(findstring s,$(OPENWRT_VERBOSE))))

ifeq ($(SDK),1)

%::
	@+$(PREP_MK) $(NO_TRACE_MAKE) -r -s prereq
	@./scripts/config/conf $(KCONF_FLAGS) --defconfig=.config Config.in
	@+$(ULIMIT_FIX) $(SUBMAKE) -r $@

else

# 这是一条 模式规则（pattern rule）允许通过正则匹配目标名，具有名字的目标叫 具名目标（explicit target），具名目标的优先级最高
# 会匹配所有非空目标
# 两个冒号表示，如果有多个同名规则，都会被执行，而不是覆盖
%::
	# @ 用于不展示该命令，简化日志
	# + 表示需要在子进程中执行
	# -r：不要使用make的一些默认值
	# -s 不要打印命令
	@+$(PREP_MK) $(NO_TRACE_MAKE) -r -s prereq
	@( \
		cp .config tmp/.config; \
		./scripts/config/conf $(KCONF_FLAGS) --defconfig=tmp/.config -w tmp/.config Config.in > /dev/null 2>&1; \
		if ./scripts/kconfig.pl '>' .config tmp/.config | grep -q CONFIG; then \
			printf "$(_R)WARNING: your configuration is out of sync. Please run make menuconfig, oldconfig or defconfig!$(_N)\n" >&2; \
		fi \
	)
	# $@ 内置变量，表示当前目标的名称，进行透传
	@+$(ULIMIT_FIX) $(SUBMAKE) -r $@ $(if $(WARN_PARALLEL_ERROR), || { \
		printf "$(_R)Build failed - please re-run with -j1 to see the real error message$(_N)\n" >&2; \
		false; \
	} )

endif

# update all feeds, re-create index files, install symlinks
package/symlinks:
	./scripts/feeds update -a
	./scripts/feeds install -a

# re-create index files, install symlinks
package/symlinks-install:
	./scripts/feeds update -i
	./scripts/feeds install -a

# remove all symlinks, don't touch ./feeds
package/symlinks-clean:
	./scripts/feeds uninstall -a

help:
	cat README.md

distclean:
	rm -rf bin build_dir .ccache .config* dl feeds key-build* logs package/feeds target/linux/feeds staging_dir tmp
	@$(_SINGLE)$(SUBMAKE) -C scripts/config clean

ifeq ($(findstring v,$(DEBUG)),)
  .SILENT: symlinkclean clean dirclean distclean config-clean download help tmpinfo-clean .config scripts/config/mconf scripts/config/conf menuconfig $(STAGING_DIR_HOST)/.prereq-build tmp/.prereq-package prepare-tmpinfo
endif
.PHONY: help FORCE
# 让 make 串行执行，不能并行
.NOTPARALLEL:

