# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2006-2010 OpenWrt.org
# Copyright (C) 2016 LEDE Project

# 避免重复引入
ifneq ($(__rules_inc),1)
__rules_inc=1

ifeq ($(DUMP),)
  -include $(TOPDIR)/.config
endif
include $(TOPDIR)/include/debug.mk
include $(TOPDIR)/include/verbose.mk

ifneq ($(filter check,$(MAKECMDGOALS)),)
CHECK:=1
DUMP:=1
endif

export TMP_DIR:=$(TOPDIR)/tmp
export TMPDIR:=$(TMP_DIR)

##@
# @brief Strip quotes `"` and pounds `#` from string.
#
# @param 1: String.
##
# $(subst ",,$(1))：将字符串中的 " 替换为空
# strip：去除字符串两端的空格
# .config 文件里的字符串通常是 CONFIG_TARGET_BOARD="x86" 这种带引号的格式，qstrip 就是把引号剥掉，得到干净的 x86
qstrip=$(strip $(subst ",,$(1)))
#"))

empty:=
space:= $(empty) $(empty)
comma:=,
pound:=\#

##@ 移除字符串中的空格，一些命令用空格区分多个参数，移除空格就是合并参数了
# @brief Merge strings by removing spaces.
#
# @param 1: String.
##
# 比如 a b c → abc。常用于把多个部分拼成文件名或标识符
merge=$(subst $(space),,$(1))
##@ 计算参数列表的hash
# @brief Get hash sum of variable list.
#
# @param 1: List of variable names.
##
# 遍历传入的参数名列表，每个参数生成字符串：VAR1=value1，value中的单引号替换为转义的单引号
# 所有变量拼接位完整字符串：VAR1=value1 VAR2=value2
# 计算上述字符串的md5
confvar=$(shell echo '$(foreach v,$(1),$(v)=$(subst ','\'',$($(v))))' | $(MKHASH) md5)
##@ 移除文件的拓展名
# @brief Strip last extension from file name.
#
# @param 1: File name.
##
strip_last=$(
  # 匹配 %.ext，将文件名匹配出来
  patsubst %.$(
    # 以空格分割，获取最后一个字符，这里得到的就是文件的拓展名
    lastword $(
      # 将 . 替换为空格
      subst .,$(space),$(1)
    )
  ),%,$(1)
)

paren_left = (
paren_right = )
chars_lower = a b c d e f g h i j k l m n o p q r s t u v w x y z
chars_upper = A B C D E F G H I J K L M N O P Q R S T U V W X Y Z

define sep

endef

define newline


endef

# 这个核心是产出 subst 替换函数的参数的，用于下面的大小写转换
# 输入：a b c,A B C
# 输出：a,A b,B c,C
__tr_list = $(
  # a, b, c, 与 A B C 进行join，得到 a,A b,B c,C
  join $(
    # 在$1每个参数后面添加逗号，得到 a, b, c,
    join $(1),$(
      # comma 是逗号，生成 $1 相同个数的逗号
      foreach char,$(1),$(comma)
    )
  ),$(2)
)

# 对生成参数拼接得到 subst 的嵌套调用
__tr_head_stripped = $(
  # 替换空格为空，得到：$(substa,A,$(substb,B,$(substc,C,
  subst $(space),,$(
    # 循环后得到 $(substa,A, $(substb,B, $(substc,C,
    foreach cv,$(
      # 生成参数对 a,A b,B c,C
      call __tr_list,$(1),$(2)
      # 拼接字符串得到 $(substa,A,
    ),$$$(paren_left)subst$(cv)$(comma)
  )
)
# 在 (subst 后面加一个空格，得到 $(subst a,A,$(subst b,B,$(subst c,C,
# 将 __tr_head_stripped 里面 (subst 替换为 (subst+空格，得到的是 $(subst a,1,
__tr_head = $(subst $(paren_left)subst,$(paren_left)subst$(space),$(__tr_head_stripped))

# 生成 $(1) 个没有空格的右括号
__tr_tail = $(subst $(space),,$(
  # 生成 $(1) 个右括号
  foreach cv,$(1),$(paren_right)
))

# 拼接字符串，得到一一映射的转换函数
# $1 和 $2 是等长的list，函数作用是一一映射
# $(subst a,A,$(subst b,B,$(subst c,C,)))
__tr_template = $(__tr_head)$$(1)$(__tr_tail)

##@小写转大写
# @brief Convert string characters to upper.
##
$(eval toupper = $(call __tr_template,$(chars_lower),$(chars_upper)))
##@ 大写转小写
# @brief Convert string characters to lower.
##
$(eval tolower = $(call __tr_template,$(chars_upper),$(chars_lower)))

##@
# @brief Abbreviate version. Truncate to 8 characters.
##
version_abbrev = $(
  if $(
    if $(CHECK),,$(DUMP)
  ),$(1),$(
    shell printf '%.8s' $(1)
  )
)

_SINGLE=export MAKEFLAGS=$(space);
CFLAGS:=
# 把 i486/i586/i686 都归一化为 i386
# 这些都是 x86 32位的变体，在 OpenWrt 的软件包分类里统一用 i386 作为包架构标识，避免同一套包因为 CPU 代际不同而被认为不兼容
ARCH:=$(subst i486,i386,$(subst i586,i386,$(subst i686,i386,$(call qstrip,$(CONFIG_ARCH)))))
ARCH_PACKAGES:=$(call qstrip,$(CONFIG_TARGET_ARCH_PACKAGES))
# 板子类型，如 x86、ath79
BOARD:=$(call qstrip,$(CONFIG_TARGET_BOARD))
# 子类型，如 64、generic
SUBTARGET:=$(call qstrip,$(CONFIG_TARGET_SUBTARGET))
# 编译优化选项，如 -O2
TARGET_OPTIMIZATION:=$(call qstrip,$(CONFIG_TARGET_OPTIMIZATION))
# 目标三元组后缀，如 musl、gnueabi
TARGET_SUFFIX=$(call qstrip,$(CONFIG_TARGET_SUFFIX))
# 构建目录后缀，用于区分多配置并存
BUILD_SUFFIX:=$(call qstrip,$(CONFIG_BUILD_SUFFIX))

# CURDIR  是makefile所在的目录
SUBDIR:=$(patsubst $(TOPDIR)/%,%,${CURDIR})
BUILD_SUBDIR:=$(patsubst $(TOPDIR)/%,%,${CURDIR})
# 获取核心数，使用了两种方式兼容
NPROC=$(shell sysctl -n hw.ncpu 2>/dev/null || nproc)
export SHELL:=/usr/bin/env bash

# 如果makefile的路径中包含 package/，则认为是包的build
IS_PACKAGE_BUILD := $(if $(filter package/%,$(BUILD_SUBDIR)),1)

# i386 变成 i486。原因是：ARCH 用来标识软件包兼容性（粗粒度），而 OPTIMIZE_FOR_CPU 用于 GCC 的 -march 参数（细粒度，让编译器生成针对具体 CPU 的指令）
OPTIMIZE_FOR_CPU=$(subst i386,i486,$(ARCH))

# 如果 ARCH 不是 aarch64 aarch64_be powerpc ，用 fPIC，否则 fpic
# -fPIC（大写）生成完全位置无关代码，开销略大但更通用；-fpic（小写）允许编译器用较小的 GOT 表做优化，但某些架构（aarch64/powerpc）的 GOT 表天然很大，小写版本会报错，所以这些架构强制用大写
ifneq (,$(findstring $(ARCH) , aarch64 aarch64_be powerpc ))
  FPIC:=-DPIC -fPIC
else
  FPIC:=-DPIC -fpic
endif

HOST_FPIC:=-DPIC -fPIC

ARCH_SUFFIX:=$(call qstrip,$(CONFIG_CPU_TYPE))
GCC_ARCH:=

# 如果不为空就加一个下划线前缀
ifneq ($(ARCH_SUFFIX),)
  ARCH_SUFFIX:=_$(ARCH_SUFFIX)
endif
ifneq ($(filter -march=armv%,$(TARGET_OPTIMIZATION)),)
  GCC_ARCH:=$(patsubst -march=%,%,$(filter -march=armv%,$(TARGET_OPTIMIZATION)))
endif
ifdef CONFIG_HAS_SPE_FPU
  TARGET_SUFFIX:=$(TARGET_SUFFIX)spe
endif
ifdef CONFIG_MIPS64_ABI
  ifneq ($(CONFIG_MIPS64_ABI_O32),y)
     ARCH_SUFFIX:=$(ARCH_SUFFIX)_$(call qstrip,$(CONFIG_MIPS64_ABI))
  endif
endif

DEFAULT_SUBDIR_TARGETS:=clean download prepare compile update refresh prereq dist distcheck configure check check-depends

##@
# @brief Create default targets.
#
# Targets are created from @DEFAULT_SUBDIR_TARGETS and input argument lists.
#
# @param 1: Additional targets list.
##
define DefaultTargets
$(foreach t,$(DEFAULT_SUBDIR_TARGETS) $(1),
  .$(t):
  $(t): .$(t)
  .PHONY: $(t) .$(t)
)
endef

# 下载文件夹
# 有 CONFIG_DOWNLOAD_FOLDER，则直接使用
# 否则使用 $(TOPDIR)/dl/

# 如果指定了 DL_SUBDIR，则在后面再追加 ${DL_SUBDIR}
# 这个没有使用 :=，是延迟推倒的，可以在后面指定相应的变量
DL_DIR=$(if
  $(call qstrip,$(CONFIG_DOWNLOAD_FOLDER)),
  $(call qstrip,$(CONFIG_DOWNLOAD_FOLDER)),
  $(TOPDIR)/dl
)$(if $(DL_SUBDIR),/$(DL_SUBDIR))

# 输出文件夹，优先使用 CONFIG_BINARY_FOLDER，默认 $(TOPDIR)/bin
# 这里输出的应该是固件
OUTPUT_DIR:=$(if
  $(call qstrip,$(CONFIG_BINARY_FOLDER)),
  $(call qstrip,$(CONFIG_BINARY_FOLDER)),
  $(TOPDIR)/bin
)
# 生成固件的目录
BIN_DIR:=$(OUTPUT_DIR)/targets/$(BOARD)/$(SUBTARGET)
INCLUDE_DIR:=$(TOPDIR)/include
SCRIPT_DIR:=$(TOPDIR)/scripts
BUILD_DIR_BASE:=$(TOPDIR)/build_dir
ifeq ($(CONFIG_EXTERNAL_TOOLCHAIN),)
  GCCV:=$(call qstrip,$(CONFIG_GCC_VERSION))
  LIBC:=$(call qstrip,$(CONFIG_LIBC))
  REAL_GNU_TARGET_NAME=$(OPTIMIZE_FOR_CPU)-openwrt-linux$(if $(TARGET_SUFFIX),-$(TARGET_SUFFIX))
  GNU_TARGET_NAME=$(OPTIMIZE_FOR_CPU)-openwrt-linux
  DIR_SUFFIX:=_$(LIBC)$(if $(CONFIG_arm),_eabi)
  BIN_DIR:=$(BIN_DIR)$(if $(CONFIG_USE_MUSL),,-$(LIBC))
  TARGET_DIR_NAME = target-$(ARCH)$(ARCH_SUFFIX)$(DIR_SUFFIX)$(if $(BUILD_SUFFIX),_$(BUILD_SUFFIX))
  TOOLCHAIN_DIR_NAME = toolchain-$(ARCH)$(ARCH_SUFFIX)_gcc-$(GCCV)$(DIR_SUFFIX)
else
  ifeq ($(CONFIG_NATIVE_TOOLCHAIN),)
    GNU_TARGET_NAME=$(call qstrip,$(CONFIG_TARGET_NAME))
  else
    GNU_TARGET_NAME=$(shell gcc -dumpmachine)
  endif
  REAL_GNU_TARGET_NAME=$(GNU_TARGET_NAME)
  LIBC:=$(call qstrip,$(CONFIG_LIBC))
  TARGET_DIR_NAME:=target-$(GNU_TARGET_NAME)_$(LIBC)$(if $(BUILD_SUFFIX),_$(BUILD_SUFFIX))
  TOOLCHAIN_DIR_NAME:=toolchain-$(GNU_TARGET_NAME)
endif

# iremap 用于可重现构建（reproducible build）。调试信息里默认会嵌入绝对路径（如/home/bob/openwrt/package/...），不同机器编译出的二进制就不同
# -ffile-prefix-map 把绝对路径替换为相对路径，让不同机器编译的结果二进制一致
ifeq ($(or $(CONFIG_EXTERNAL_TOOLCHAIN),$(CONFIG_TARGET_uml)),)
  iremap = -f$(if $(CONFIG_REPRODUCIBLE_DEBUG_INFO),file,macro)-prefix-map=$(1)=$(2)
endif

# 目录结构变量
#   TOPDIR/
#   ├── build_dir/           ← BUILD_DIR_BASE                                                                                    
#   │   ├── target-xxx/      ← BUILD_DIR（目标包的编译工作区）                                                                   
#   │   ├── toolchain-xxx/   ← BUILD_DIR_TOOLCHAIN                                                                               
#   │   └── host/            ← BUILD_DIR_HOST（宿主机工具的编译区）                                                              
#   ├── staging_dir/         ← 安装各种头文件/库的"假根目录"                                                                     
#   │   ├── target-xxx/      ← STAGING_DIR                                                                                       
#   │   ├── toolchain-xxx/   ← TOOLCHAIN_DIR                                                                                     
#   │   └── host/            ← STAGING_DIR_HOST                                                                                  
#   ├── bin/                 ← OUTPUT_DIR                                                                                        
#   │   └── targets/board/subtarget/ ← BIN_DIR（最终固件）                                                                       
#   ├── dl/                  ← DL_DIR（源码压缩包缓存）                                                                          
#   └── tmp/                 ← TMP_DIR

# 为什么要分这么多目录？ 交叉编译有三个不同的"世界"：
#   1. 宿主机（host）：跑在你电脑上的工具，如 sed、mkhash
#   2. 工具链（toolchain）：交叉编译器本身，aarch64-openwrt-linux-gcc
#   3. 目标（target）：要跑在路由器上的程序
# 三者头文件和库完全不能混用，分目录是强制隔离的手段。

PACKAGE_DIR?=$(BIN_DIR)/packages
PACKAGE_DIR_ALL?=$(TOPDIR)/staging_dir/packages/$(BOARD)
BUILD_DIR:=$(BUILD_DIR_BASE)/$(TARGET_DIR_NAME)
STAGING_DIR:=$(TOPDIR)/staging_dir/$(TARGET_DIR_NAME)
BUILD_DIR_TOOLCHAIN:=$(BUILD_DIR_BASE)/$(TOOLCHAIN_DIR_NAME)
TOOLCHAIN_DIR:=$(TOPDIR)/staging_dir/$(TOOLCHAIN_DIR_NAME)
STAMP_DIR:=$(BUILD_DIR)/stamp
STAMP_DIR_HOST=$(BUILD_DIR_HOST)/stamp
TARGET_ROOTFS_DIR?=$(if $(call qstrip,$(CONFIG_TARGET_ROOTFS_DIR)),$(call qstrip,$(CONFIG_TARGET_ROOTFS_DIR)),$(BUILD_DIR))
TARGET_DIR:=$(TARGET_ROOTFS_DIR)/root-$(BOARD)
STAGING_DIR_ROOT:=$(STAGING_DIR)/root-$(BOARD)
STAGING_DIR_IMAGE:=$(STAGING_DIR)/image
BUILD_LOG_DIR:=$(if $(call qstrip,$(CONFIG_BUILD_LOG_DIR)),$(call qstrip,$(CONFIG_BUILD_LOG_DIR)),$(TOPDIR)/logs)
PKG_INFO_DIR := $(STAGING_DIR)/pkginfo

BUILD_DIR_HOST:=$(if $(IS_PACKAGE_BUILD),$(BUILD_DIR_BASE)/hostpkg,$(BUILD_DIR_BASE)/host)
STAGING_DIR_HOST:=$(abspath $(STAGING_DIR)/../host)
STAGING_DIR_HOSTPKG:=$(abspath $(STAGING_DIR)/../hostpkg)

# 这里做了两件事：
#   1. 清理系统 PATH：把 . 和 ./ 从 PATH 里移除。这是安全实践——如果当前目录在 PATH 里，攻击者放一个同名的恶意程序就能被执行。
#   2. 注入工具链路径：TOOLCHAIN_BIN_DIRS 被加到 PATH 最前面，确保构建时优先使用 OpenWrt 自己的工具，而不是系统的 gcc（系统 gcc是宿主机的，不能交叉编译）。
TARGET_PATH:=$(subst $(space),:,$(filter-out .,$(filter-out ./,$(subst :,$(space),$(PATH)))))
TARGET_INIT_PATH:=$(call qstrip,$(CONFIG_TARGET_INIT_PATH))
TARGET_INIT_PATH:=$(if $(TARGET_INIT_PATH),$(TARGET_INIT_PATH),/usr/sbin:/sbin:/usr/bin:/bin)
# TARGET_CFLAGS 是给目标设备上的 C 代码用的编译选项，包含优化级别（如 -O2）。-g3 是调试符号，只在 CONFIG_DEBUG 时加入，因为调试符号会显著增大固件体积。
TARGET_CFLAGS:=$(TARGET_OPTIMIZATION)$(if $(CONFIG_DEBUG), -g3) $(call qstrip,$(CONFIG_EXTRA_OPTIMIZATION))
TARGET_CXXFLAGS = $(TARGET_CFLAGS)
TARGET_ASFLAGS_DEFAULT = $(TARGET_CFLAGS)
TARGET_ASFLAGS = $(TARGET_ASFLAGS_DEFAULT)
ifneq ($(CONFIG_EXTERNAL_TOOLCHAIN),)

# Library GCC Shared Path，链接共享库的路径
# realpath 将相对路径转为绝对路径，并跟随符号解析到真正的文件
LIBGCC_S_PATH=$(realpath
  # 使用 wildcard，可能是因为 CONFIG_LIBGCC_ROOT_DIR 或 CONFIG_LIBGCC_FILE_SPEC 包含匹配，需要转为真正的路径
  $(wildcard $(
    call qstrip,$(CONFIG_LIBGCC_ROOT_DIR)
  )/$(call qstrip,$(CONFIG_LIBGCC_FILE_SPEC))))

# Library GCC Shared，链接共享库
LIBGCC_S=$(if
  $(LIBGCC_S_PATH),
  -L$(dir $(LIBGCC_S_PATH)) -lgcc_s
)
# Library GCC Archive，表示gcc的静态库（archive library）
LIBGCC_A=$(realpath $(lastword $(wildcard $(dir $(LIBGCC_S_PATH))/gcc/*/*/libgcc.a)))
else
LIBGCC_A=$(lastword $(wildcard $(TOOLCHAIN_DIR)/lib/gcc/*/*/libgcc.a))
LIBGCC_S=$(if $(wildcard $(TOOLCHAIN_DIR)/lib/libgcc_s.so),-L$(TOOLCHAIN_DIR)/lib -lgcc_s,$(LIBGCC_A))
endif

ifeq ($(CONFIG_ARCH_64BIT),y)
  LIB_SUFFIX:=64
endif

ifndef DUMP
  ifeq ($(CONFIG_EXTERNAL_TOOLCHAIN),)
    # /openwrt/staging_dir/toolchain-aarch64_cortex-a53_gcc-14.3.0_musl/info.mk
    -include $(TOOLCHAIN_DIR)/info.mk
    export GCC_HONOUR_COPTS:=0
    # 这是交叉编译器的前缀，比如 aarch64-openwrt-linux-musl-。所有交叉编译工具都以它为前缀
    TARGET_CROSS:=$(if $(TARGET_CROSS),$(TARGET_CROSS),$(OPTIMIZE_FOR_CPU)-openwrt-linux$(if $(TARGET_SUFFIX),-$(TARGET_SUFFIX))-)
    TOOLCHAIN_ROOT_DIR:=$(TOPDIR)/staging_dir/$(TOOLCHAIN_DIR_NAME)
    TOOLCHAIN_BIN_DIRS:=$(TOOLCHAIN_ROOT_DIR)/bin
    TOOLCHAIN_INC_DIRS:=$(TOOLCHAIN_ROOT_DIR)/usr/include $(TOOLCHAIN_ROOT_DIR)/include
    TOOLCHAIN_LIB_DIRS:=$(TOOLCHAIN_ROOT_DIR)/usr/lib $(TOOLCHAIN_ROOT_DIR)/lib
    TARGET_CFLAGS+= -fhonour-copts
    ifeq ($(CONFIG_USE_MUSL),y)
      TOOLCHAIN_INC_DIRS+= $(TOOLCHAIN_DIR)/include/fortify
    endif
  else
    ifeq ($(CONFIG_NATIVE_TOOLCHAIN),)
      # /openwrt/staging_dir/toolchain-aarch64_cortex-a53_gcc-14.3.0_musl/info.mk
      -include $(TOOLCHAIN_DIR)/info.mk
      TARGET_CROSS:=$(call qstrip,$(CONFIG_TOOLCHAIN_PREFIX))
      TOOLCHAIN_ROOT_DIR:=$(call qstrip,$(CONFIG_TOOLCHAIN_ROOT))
      TOOLCHAIN_BIN_DIRS:=$(patsubst ./%,$(TOOLCHAIN_ROOT_DIR)/%,$(call qstrip,$(CONFIG_TOOLCHAIN_BIN_PATH)))
      TOOLCHAIN_INC_DIRS:=$(patsubst ./%,$(TOOLCHAIN_ROOT_DIR)/%,$(call qstrip,$(CONFIG_TOOLCHAIN_INC_PATH)))
      TOOLCHAIN_LIB_DIRS:=$(patsubst ./%,$(TOOLCHAIN_ROOT_DIR)/%,$(call qstrip,$(CONFIG_TOOLCHAIN_LIB_PATH)))
    endif
  endif
  ifneq ($(TOOLCHAIN_BIN_DIRS),)
    TARGET_PATH:=$(subst $(space),:,$(TOOLCHAIN_BIN_DIRS)):$(TARGET_PATH)
  endif
  ifneq ($(TOOLCHAIN_INC_DIRS),)
    TARGET_CPPFLAGS+= $(patsubst %,-I%,$(TOOLCHAIN_INC_DIRS))
  endif
  ifneq ($(TOOLCHAIN_LIB_DIRS),)
    TARGET_LDFLAGS+= $(patsubst %,-L%,$(TOOLCHAIN_LIB_DIRS))
  endif
endif

TARGET_LINKER?=bfd
TARGET_LDFLAGS+= -fuse-ld=$(TARGET_LINKER)

TARGET_PATH_PKG:=$(STAGING_DIR)/host/bin:$(STAGING_DIR_HOSTPKG)/bin:$(TARGET_PATH)

ifeq ($(CONFIG_SOFT_FLOAT),y)
  SOFT_FLOAT_CONFIG_OPTION:=--with-float=soft
  # 浮点处理有三种模式：soft（全软件模拟）、softfp（ABI软浮点但用FPU指令）、hard（硬件FPU + 专用寄存器传参）。路由器芯片有的没有FPU，必须软浮点；有的带了 FPU 就用硬件，性能差很多。编译时必须和 C 库保持一致，混用会导致链接失败或运行时崩溃
  ifeq ($(CONFIG_arm),y)
    # ARM: 纯软件浮点
    TARGET_CFLAGS+= -mfloat-abi=soft
  else
    # ARM: 硬件 FPU
    TARGET_CFLAGS+= -msoft-float
  endif
else
  SOFT_FLOAT_CONFIG_OPTION:=
  ifeq ($(CONFIG_arm),y)
    TARGET_CFLAGS+= -mfloat-abi=hard
  endif
endif

export ORIG_PATH:=$(if $(ORIG_PATH),$(ORIG_PATH),$(PATH))
export PATH:=$(TARGET_PATH)
export STAGING_DIR STAGING_DIR_HOST STAGING_DIR_HOSTPKG
export SH_FUNC:=. $(INCLUDE_DIR)/shell.sh;

PKG_CONFIG:=$(STAGING_DIR_HOST)/bin/pkg-config

export PKG_CONFIG

HOST_FLAGS_OPT:=$(if $(CONFIG_OPTIMIZE_HOST_TOOLS),$(call qstrip,$(CONFIG_HOST_FLAGS_OPT)),-O2)
HOST_FLAGS_STRIP:=$(call qstrip,$(CONFIG_HOST_FLAGS_STRIP))
HOST_EXTRA_CFLAGS:=$(call qstrip,$(CONFIG_HOST_EXTRA_CFLAGS))
HOST_EXTRA_CXXFLAGS:=$(call qstrip,$(CONFIG_HOST_EXTRA_CXXFLAGS))
HOST_EXTRA_CPPFLAGS:=$(call qstrip,$(CONFIG_HOST_EXTRA_CPPFLAGS))
HOST_EXTRA_LDFLAGS:=$(call qstrip,$(CONFIG_HOST_EXTRA_LDFLAGS))

HOSTCC:=$(STAGING_DIR_HOST)/bin/gcc
HOSTCXX:=$(STAGING_DIR_HOST)/bin/g++
HOST_CPPFLAGS:=$(strip -I$(STAGING_DIR_HOST)/include $(if $(IS_PACKAGE_BUILD),-I$(STAGING_DIR_HOSTPKG)/include -I$(STAGING_DIR)/host/include) $(HOST_EXTRA_CPPFLAGS))
HOST_CFLAGS:=$(strip $(HOST_FLAGS_OPT) $(HOST_EXTRA_CFLAGS) $(HOST_CPPFLAGS) $(HOST_FLAGS_STRIP))
HOST_CXXFLAGS:=$(strip $(HOST_CFLAGS) $(HOST_EXTRA_CXXFLAGS))
HOST_LDFLAGS:=$(strip -L$(STAGING_DIR_HOST)/lib $(if $(IS_PACKAGE_BUILD),-L$(STAGING_DIR_HOSTPKG)/lib -L$(STAGING_DIR)/host/lib) $(HOST_EXTRA_LDFLAGS) $(HOST_FLAGS_STRIP))

# OpenWrt 的包管理器在安装前会验证包签名，防止被篡改。key-build 是你自己构建时生成的密钥，安装到固件后路由器只信任用这个 key 签名的包
# opkg 包签名私钥
BUILD_KEY=$(TOPDIR)/key-build
# APK 格式包签名私钥
BUILD_KEY_APK_SEC=$(TOPDIR)/private-key.pem
# APK 格式包签名公钥
BUILD_KEY_APK_PUB=$(TOPDIR)/public-key.pem

FAKEROOT:=$(STAGING_DIR_HOST)/bin/fakeroot

# 为什么用 gcc-ar 而不是 ar？
# gcc-ar 是 GCC 的封装版，支持 LTO（链接时优化）。普通 ar 不理解 LTO 的中间格式，链接时会出问题。
TARGET_AR:=$(TARGET_CROSS)gcc-ar
TARGET_RANLIB:=$(TARGET_CROSS)gcc-ranlib
TARGET_NM:=$(TARGET_CROSS)gcc-nm
TARGET_CC:=$(TARGET_CROSS)gcc
TARGET_CXX:=$(TARGET_CROSS)g++
TARGET_LD:=$(TARGET_CROSS)ld.$(TARGET_LINKER)
KPATCH:=$(SCRIPT_DIR)/patch-kernel.sh
FILECMD:=$(STAGING_DIR_HOST)/bin/file
SED:=$(STAGING_DIR_HOST)/bin/sed -i -e
ESED:=$(STAGING_DIR_HOST)/bin/sed -E -i -e
MKHASH:=$(STAGING_DIR_HOST)/bin/mkhash
# MKHASH is used in /scripts, so we export it here.
export MKHASH
CP:=cp -fpR
LN:=ln -sf
XARGS:=xargs -r

BASH:=bash
TAR:=tar
FIND:=find
PATCH:=patch
PYTHON:=python3

ifeq ($(HOST_OS),Darwin)
  TRUE:=/usr/bin/env gtrue
  FALSE:=/usr/bin/env gfalse
else
  TRUE:=/usr/bin/env true
  FALSE:=/usr/bin/env false
endif

# 可执行文件，权限 755
INSTALL_BIN:=install -m0755
# setuid 可执行，4 表示 setuid bit
INSTALL_SUID:=install -m4755
INSTALL_DIR:=install -d -m0755
# 数据文件，不可执行
INSTALL_DATA:=install -m0644
# 配置文件，只有 root 可读
INSTALL_CONF:=install -m0600

TARGET_CC_NOCACHE:=$(TARGET_CC)
TARGET_CXX_NOCACHE:=$(TARGET_CXX)
HOSTCC_NOCACHE:=$(HOSTCC)
HOSTCXX_NOCACHE:=$(HOSTCXX)
export TARGET_CC_NOCACHE
export TARGET_CXX_NOCACHE
export HOSTCC_NOCACHE
export HOSTCXX_NOCACHE

# 使用 ccache 对编译结果进行缓存
# ccache 把编译结果缓存到磁盘，相同源文件+相同编译参数直接复用缓存，可以大幅加速重复构建
ifneq ($(CONFIG_CCACHE),)
  TARGET_CC:= ccache $(TARGET_CC)
  TARGET_CXX:= ccache $(TARGET_CXX)
  HOSTCC:= ccache $(HOSTCC)
  HOSTCXX:= ccache $(HOSTCXX)
  export CCACHE_NOCOMPRESS:=true
  # CCACHE_BASEDIR 设为项目根目录，让 ccache 在比较缓存键时用相对路径，这样即使项目换了位置，缓存依然有效
  export CCACHE_BASEDIR:=$(TOPDIR)
  export CCACHE_DIR:=$(if $(call qstrip,$(CONFIG_CCACHE_DIR)),$(call qstrip,$(CONFIG_CCACHE_DIR)),$(TOPDIR)/.ccache)
  # CCACHE_COMPILERCHECK 用编译器版本号做 key 的一部分，换了编译器版本就会让旧缓存失效
  export CCACHE_COMPILERCHECK:=%compiler% -v -c
endif

TARGET_CONFIGURE_OPTS = \
  AR="$(TARGET_AR)" \
  AS="$(TARGET_CC) -c $(TARGET_ASFLAGS)" \
  LD="$(TARGET_LD)" \
  NM="$(TARGET_NM)" \
  CC="$(TARGET_CC)" \
  GCC="$(TARGET_CC)" \
  CXX="$(TARGET_CXX)" \
  RANLIB="$(TARGET_RANLIB)" \
  STRIP=$(TARGET_CROSS)strip \
  OBJCOPY=$(TARGET_CROSS)objcopy \
  OBJDUMP=$(TARGET_CROSS)objdump \
  SIZE=$(TARGET_CROSS)size

# strip an entire directory
ifneq ($(CONFIG_NO_STRIP),)
  # : 是 shell 的 no-op，什么都不做
  RSTRIP:=:
  STRIP:=:
else
  # strip 去掉二进制文件里的调试符号和符号表，路由器 flash 空间宝贵，一个包去掉符号后体积能缩小 60-80%
  ifneq ($(CONFIG_USE_STRIP),)
    STRIP:=$(TARGET_CROSS)strip $(call qstrip,$(CONFIG_STRIP_ARGS))
  else
    # sstrip（super strip，比 strip 更激进）
    ifneq ($(CONFIG_USE_SSTRIP),)
      STRIP:=$(STAGING_DIR_HOST)/bin/sstrip $(if $(CONFIG_SSTRIP_DISCARD_TRAILING_ZEROES),-z)
    endif
  endif
  # RSTRIP 是递归 strip，通过 rstrip.sh 脚本处理整个目录，还会调用 patchelf 修复动态库依赖路径。KEEP_BUILD_ID=1 表示保留 Build ID（一个小的 hash），方便事后用 addr2line 对 crash 地址还原符号（即使已经 strip 了）
  RSTRIP= \
    export CROSS="$(TARGET_CROSS)" \
		$(if $(PKG_BUILD_ID),KEEP_BUILD_ID=1) \
		$(if $(CONFIG_KERNEL_KALLSYMS),NO_RENAME=1) \
		$(if $(CONFIG_KERNEL_PROFILING),KEEP_SYMBOLS=1); \
    # nm 用于列出目标文件的符号表
    NM="$(TARGET_CROSS)nm" \
    STRIP="$(STRIP)" \
    STRIP_KMOD="$(SCRIPT_DIR)/strip-kmod.sh" \
    PATCHELF="$(STAGING_DIR_HOST)/bin/patchelf" \
    $(SCRIPT_DIR)/rstrip.sh
endif

NINJA = \
	MAKEFLAGS="$(MAKE_JOBSERVER)" \
	$(STAGING_DIR_HOST)/bin/ninja \
		$(if $(findstring c,$(OPENWRT_VERBOSE)),-v) \
		$(if $(MAKE_JOBSERVER),,-j1)

ifeq ($(CONFIG_IPV6),y)
  DISABLE_IPV6:=
else
  DISABLE_IPV6:=--disable-ipv6
endif

TAR_OPTIONS:=-xf -

ifeq ($(CONFIG_BUILD_LOG),y)
  BUILD_LOG:=1
endif

export BISON_PKGDATADIR:=$(STAGING_DIR_HOST)/share/bison
export HOST_GNULIB_SRCDIR:=$(STAGING_DIR_HOST)/share/gnulib
# 宏处理器，通常用于生成文本文件
export M4:=$(STAGING_DIR_HOST)/bin/m4

##@ 将字符串中的 .-/ 替换为 _，貌似是根据输出生成一个变量名，前缀 V_ 是为了确保变量名是合法的，避免输入是数字开头的
# @brief Slugify variable name and prepend suffix.
##
define shvar
V_$(subst .,_,$(subst -,_,$(subst /,_,$(1))))
endef

##@ 将输入转为变量，并 export 出去
# call shexport, a/b，会得到  export V_a_b=a/b
# @brief Create and export variable, set to function result.
#
# @param 1: Function name. Used as variable name, prepended with `V_`.
##
define shexport
export $(call shvar,$(1))=$$(call $(1))
endef

##@ 检查 host 是否支持64位的时间
# @brief Support 64 bit tine in C code.
#
# Test support for 64-bit time with C code from largefile.m4 provided by GNU Gnulib
# the value is `y` when successful and `` otherwise
##
define YEAR_2038
$(shell \
  mkdir -p $(TMP_DIR); \
  echo '$(pound) include <time.h>' > $(TMP_DIR)/year2038.c; \
  echo '$(pound) define LARGE_TIME_T ((time_t) (((time_t) 1 << 30) - 1 + 3 * ((time_t) 1 << 30)))' >> $(TMP_DIR)/year2038.c; \
  echo 'int verify_time_t_range[(LARGE_TIME_T / 65537 == 65535 && LARGE_TIME_T % 65537 == 0) ? 1 : -1];' >> $(TMP_DIR)/year2038.c; \
  echo 'int main (void) {return 0;}' >> $(TMP_DIR)/year2038.c; \
  $(HOSTCC) $(TMP_DIR)/year2038.c -o /dev/null 2>/dev/null && echo y && rm -f $(TMP_DIR)/year2038.c || rm -f $(TMP_DIR)/year2038.c; \
)
endef

# flock 是文件锁。并行构建时，多个 make 进程可能同时写同一个文件（如 staging_dir），locked 宏确保某些操作是串行的。如果系统没有 flock，直接执行（降级处理，接受竞态风险）。
##@ 检查是否支持 flock，并兜底
# @brief Execute commands under flock
#
# @param 1: The shell expression.
# @param 2: The lock name. If not given, the global lock will be used.
##
ifneq ($(wildcard $(STAGING_DIR_HOST)/bin/flock),)
  define locked
	SHELL= \
	flock \
		$(TMP_DIR)/.$(if
      $(2),
      $(strip $(2)),
      global
    ).flock \
    # -c：指定要执行的脚本
		-c '$(subst ','\'',$(1))'
  endef
else
  # 不支持 flock 直接执行 $1
  locked=$(1)
endif


##@ 将 $1 拷贝到 $2 中，拷贝之前，如果 $2 中是符号链接，直接删除
# @brief Recursively copy paths into another directory, purge dangling
# symlinks before.
#
# @param 1: File glob expression.
# @param 1: Destination directory.
##
define file_copy
  # 根据 $1 得到所有的文件
  # 遍历文件，得到文件夹
  # 排序
	for src_dir in $(sort $(foreach d,$(wildcard $(1)),$(dir $(d)))); do \
    # 找到所有 文件 和 目录
		( cd $$src_dir; find -type f -or -type d ) | \
      # 进入目标目录
			( cd $(2); while :; do \
        # 从管道中读取出一个参数，这里是文件名
				read FILE; \
        # 如果文件为空，循环结束，直接退出
				[ -z "$$FILE" ] && break; \
        # 如果不是符号链接，跳过
				[ -L "$$FILE" ] || continue; \
        # 到这里说明是符号链接
				echo "Removing symlink $(2)/$$FILE"; \
        # 删除
				rm -f "$$FILE"; \
			done; ); \
	done; \
	$(CP) $(1) $(2)
endef

##@ 计算整个文件夹的 sha256sum，写入到 sha256sums 文件中
# @brief Calculate sha256sum of any plain file within a given directory.
#
# @param 1: Input directory.
# @param 2: If set, recurse into subdirectories.
##
define sha256sums
  # printf 的 %P 是相对路径
  # 找到所有文件的相对路径
  # 排序
  # 计算相对路径的 sha256
	(cd $(1); find . $(if $(2),,-maxdepth 1) -type f -not -name 'sha256sums' -printf "%P\n" | sort | \
    # s!...!...!：sed 的替换命令，s 表示替换，! 是分隔符，可以用其他字符代替，如 /。在这里，! 用于避免与路径中的斜杠冲突
		xargs -r $(MKHASH) -n sha256 | sed -ne 's!^\(.*\) \(.*\)$$!\1 *\2!p' > sha256sums)
endef

##@ 获取文件的拓展名
# @brief Retrieve file extension.
#
# @param 1: File name.
##
# word 用于在指定字符中获取第几个单词
# 文件名 file.name.txt 会先被转为 file name txt
# words得到共有 3 个单词
# word获取到第三个就是文件的拓展名，就是最后一个
ext=$(word $
  # words 计算单词个数，空格隔开算一下
  # a b c 会输出 3
  (words $(
    # 将 . 替换位空格
    subst ., ,$(1)
  )),
  $(subst ., ,$(1))
)

##@
# @brief Count Git commits of a package.
#
# @param 1: if non-empty: count commits since last ": [uU]pdate to "
#           or ": [bB]ump to " in commit message.
##
define commitcount
$(shell \
  if git log -1 --no-show-signature >/dev/null 2>/dev/null; then \
    if [ -n "$(1)" ]; then \
      $(call ERROR_MESSAGE,DEPRECATION NOTICE: The use of AUTORELEASE has been deprecated. Fix your Makefile.); \
      last_bump="$$(git log --no-show-signature --pretty=format:'%h %s' . | \
        grep -m 1 -e ': [uU]pdate to ' -e ': [bB]ump to ' | \
        cut -f 1 -d ' ')"; \
    fi; \
    if [ -n "$$last_bump" ]; then \
      echo -n $$(($$(git rev-list --count "$$last_bump..HEAD" .) + 1)); \
    else \
      git rev-list --count HEAD .; \
    fi; \
  else \
    secs="$$(($(SOURCE_DATE_EPOCH) % 86400))"; \
    date="$$(date --utc --date="@$(SOURCE_DATE_EPOCH)" "+%y%m%d")"; \
    printf '%s.%05d' "$$date" "$$secs"; \
  fi; \
)
endef

##@
# @brief Get ABI version string, stripping `-`, `_` and `.`.
#
# @param 1: Version string.
##
abi_version_str = $(subst -,,$(subst _,,$(subst .,,$(1))))

COMMITCOUNT = $(if $(DUMP),0,$(call commitcount))
AUTORELEASE = $(if $(DUMP),0,$(call commitcount,1))

all:
FORCE: ;
.PHONY: FORCE

check: FORCE
	@true

# 这两个是调试用的通配目标：
#   - make val.ARCH → 直接打印变量值：aarch64
#   - make var.ARCH → 打印带变量名：ARCH='aarch64'（适合 eval 导入）
val.%:
  # $* 是自动变量，代表模式规则中 % 的匹配部分
  # origin 函数用于确定变量 $* 的来源，如果是 undefined，说明没有定义
	@$(if $(filter undefined,$(origin $*)),\
		echo "$* undefined" >&2, \
    # 变量有定义的话，输出变量的值，将单引号处理为双引号
		echo '$(subst ','"'"',$($*))' \
	)

var.%:
	@$(if $(filter undefined,$(origin $*)),\
		echo "$* undefined" >&2, \
		echo "$*='"'$(subst ','"'\"'\"'"',$($*))'"'" \
	)

endif #__rules_inc
