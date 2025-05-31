# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2007-2008 OpenWrt.org
# Copyright (C) 2016 LEDE Project

ifneq ($(__target_inc),1)
__target_inc=1


##@
# @brief Default device type ( basic | nas | router ).
##
DEVICE_TYPE?=router

##@
# @brief Default packages.
#
# The really basic set. Additional packages are added based on @DEVICE_TYPE and
# @CONFIG_* values.
##
DEFAULT_PACKAGES:=\
	base-files \
	ca-bundle \
	dropbear \
	fstools \
	libc \
	libgcc \
	libustream-mbedtls \
	logd \
	mtd \
	netifd \
	uci \
	uclient-fetch \
	urandom-seed \
	urngd

##@
# @brief Default packages for @DEVICE_TYPE basic.
##
DEFAULT_PACKAGES.basic:=
##@
# @brief Default packages for @DEVICE_TYPE nas.
##
DEFAULT_PACKAGES.nas:=\
	block-mount \
	fdisk \
	lsblk \
	mdadm
##@
# @brief Default packages for @DEVICE_TYPE router.
##
DEFAULT_PACKAGES.router:=\
	dnsmasq \
	firewall4 \
	nftables \
	kmod-nft-offload \
	odhcp6c \
	odhcpd-ipv6only \
	ppp \
	ppp-mod-pppoe

ifneq ($(DUMP),)
  all: dumpinfo
endif

# $(subst from,to,text)：将text中将所有的from字符串替换为to字符串
# 将参数中的 .-/ 替换为 _
target_conf=$(subst
  .,
  _,
  $(subst
    -,
    _,
    $(subst
      /,
      _,
      $(1)
    )
  )
)
ifeq ($(DUMP),)
  # 获取平台的文件夹，feeds 的优先级要高于系统内置的
  PLATFORM_DIR:=$(firstword $(wildcard $(TOPDIR)/target/linux/feeds/$(BOARD) $(TOPDIR)/target/linux/$(BOARD)))
  # 获取平台的子目标，像 x86 会细分 64位 和 32位
  SUBTARGET:=$(strip
    $(foreach
      subdir,
      # 获取到子平台的目录名
      $(patsubst
        $(PLATFORM_DIR)/%/target.mk,
        %,
        # 查找到所有的子平台 target.mk
        $(wildcard
          $(PLATFORM_DIR)/*/target.mk
        )
      ),
      $(if
        $(CONFIG_TARGET_$(call target_conf,$(BOARD)_$(subdir))
        ),
        $(subdir)
      )
    )
  )
else
  # 如果是 DUMP 的话，在哪个文件夹就分析哪个文件夹
  PLATFORM_DIR:=${CURDIR}
  ifeq ($(SUBTARGETS),)
    SUBTARGETS:=$(strip $(patsubst $(PLATFORM_DIR)/%/target.mk,%,$(wildcard $(PLATFORM_DIR)/*/target.mk)))
  endif
endif

# 拼接主板和子目标
TARGETID:=$(BOARD)$(if $(SUBTARGET),/$(SUBTARGET))
# 平台的子目录
PLATFORM_SUBDIR:=$(PLATFORM_DIR)$(if $(SUBTARGET),/$(SUBTARGET))

# 引用 主文件的 makefile，引用子目录的 target.mk
ifneq ($(TARGET_BUILD),1)
  ifndef DUMP
    include $(PLATFORM_DIR)/Makefile
    ifneq ($(PLATFORM_DIR),$(PLATFORM_SUBDIR))
      include $(PLATFORM_SUBDIR)/target.mk
    endif
  endif
else
  ifneq ($(SUBTARGET),)
    -include ./$(SUBTARGET)/target.mk
  endif
endif

# 只在有足够存储的机器上才启用 ujail
# include ujail on systems with enough storage
ifeq ($(filter small_flash,$(FEATURES)),)
  DEFAULT_PACKAGES+=procd-ujail
endif

# Add device specific packages (here below to allow device type set from subtarget)
# DEFAULT_PACKAGES.$(DEVICE_TYPE) 是拼接出来的变量名，允许在子目标中添加额外的包
DEFAULT_PACKAGES += $(DEFAULT_PACKAGES.$(DEVICE_TYPE))

##@
# @brief Filter out packages, prepended with `-`.
#
# @param 1: Package list.
##

# 整体功能是把 $(1) 中以 - 开头的内容删掉
filter_packages = $(filter-out
  # patsubst 是获取 - 后面的内容
  -% $(patsubst
    -%,
    %,
    # 只保留以 - 开头的元素
    $(filter
      -%,
      $(1)
    )
  ),
  $(1)
)

##@
# @brief Append extra package dependencies.
#
# @param 1: Package list.
##
# 如果$1中有 wpad、以 wpad- 开头、nas 的元素，就将 iwinfo 添加到 extra_packages 中
extra_packages = $(if
  # 保留 wpad、以 wpad- 开头、nas 的元素
  $(filter wpad wpad-% nas,$(1)),
  iwinfo
)

define ProfileDefault
  NAME:=
  PRIORITY:=
  PACKAGES:=
endef

ifndef Profile
define Profile
  $(eval $(call ProfileDefault))
  $(eval $(call Profile/$(1)))
  dumpinfo : $(call shexport,Profile/$(1)/Description)
  PACKAGES := $(filter-out -%,$(PACKAGES))
  DUMPINFO += \
	echo "Target-Profile: $(1)"; \
	$(if $(PRIORITY), echo "Target-Profile-Priority: $(PRIORITY)"; ) \
	echo "Target-Profile-Name: $(NAME)"; \
	echo "Target-Profile-Packages: $(PACKAGES) $(call extra_packages,$(DEFAULT_PACKAGES) $(PACKAGES))"; \
	echo "Target-Profile-Description:"; \
	echo "$$$$$$$$$(call shvar,Profile/$(1)/Description)"; \
	echo "@@"; \
	echo;
endef
endif

# 这个对比应该是确定也没有子目标的
ifneq ($(PLATFORM_DIR),$(PLATFORM_SUBDIR))
  # 有子目标走这个
  define IncludeProfiles
    -include $(sort $(wildcard $(PLATFORM_DIR)/profiles/*.mk))
    -include $(sort $(wildcard $(PLATFORM_SUBDIR)/profiles/*.mk))
  endef
else
  define IncludeProfiles
    -include $(sort $(wildcard $(PLATFORM_DIR)/profiles/*.mk))
  endef
endif

PROFILE?=$(call qstrip,$(CONFIG_TARGET_PROFILE))

ifeq ($(TARGET_BUILD),1)
  ifneq ($(DUMP),)
    $(eval $(call IncludeProfiles))
  endif
endif

GENERIC_PLATFORM_DIR := $(TOPDIR)/target/linux/generic

ifneq ($(TARGET_BUILD)$(if $(DUMP),,1),)
  include $(INCLUDE_DIR)/kernel-version.mk
endif

GENERIC_BACKPORT_DIR := $(GENERIC_PLATFORM_DIR)/backport$(if $(wildcard $(GENERIC_PLATFORM_DIR)/backport-$(KERNEL_PATCHVER)),-$(KERNEL_PATCHVER))
GENERIC_PATCH_DIR := $(GENERIC_PLATFORM_DIR)/pending$(if $(wildcard $(GENERIC_PLATFORM_DIR)/pending-$(KERNEL_PATCHVER)),-$(KERNEL_PATCHVER))
GENERIC_HACK_DIR := $(GENERIC_PLATFORM_DIR)/hack$(if $(wildcard $(GENERIC_PLATFORM_DIR)/hack-$(KERNEL_PATCHVER)),-$(KERNEL_PATCHVER))
GENERIC_FILES_DIR := $(foreach dir,$(wildcard $(GENERIC_PLATFORM_DIR)/files $(GENERIC_PLATFORM_DIR)/files-$(KERNEL_PATCHVER)),"$(dir)")

__config_name_list = $(1)/config-$(KERNEL_PATCHVER) $(1)/config-default
# 有优先级，取第一个
__config_list = $(firstword $(wildcard $(call __config_name_list,$(1))))
find_kernel_config=$(if $(__config_list),$(__config_list),$(lastword $(__config_name_list)))

GENERIC_LINUX_CONFIG = $(call find_kernel_config,$(GENERIC_PLATFORM_DIR))
LINUX_TARGET_CONFIG = $(call find_kernel_config,$(PLATFORM_DIR))
ifneq ($(PLATFORM_DIR),$(PLATFORM_SUBDIR))
  LINUX_SUBTARGET_CONFIG = $(call find_kernel_config,$(PLATFORM_SUBDIR))
endif

# 所有内核的配置文件
# config file list used for compiling
LINUX_KCONFIG_LIST = $(wildcard $(GENERIC_LINUX_CONFIG) $(LINUX_TARGET_CONFIG) $(LINUX_SUBTARGET_CONFIG) $(TOPDIR)/env/kernel-config)

# default config list for reconfiguring
# defaults to subtarget if subtarget exists and target does not
# defaults to target otherwise
USE_SUBTARGET_CONFIG = $(if $(wildcard $(LINUX_TARGET_CONFIG)),,$(if $(LINUX_SUBTARGET_CONFIG),1))

LINUX_RECONFIG_LIST = $(wildcard $(GENERIC_LINUX_CONFIG) $(LINUX_TARGET_CONFIG) $(if $(USE_SUBTARGET_CONFIG),$(LINUX_SUBTARGET_CONFIG)))
LINUX_RECONFIG_TARGET = $(if $(USE_SUBTARGET_CONFIG),$(LINUX_SUBTARGET_CONFIG),$(LINUX_TARGET_CONFIG))

CFG_TARGET = $(CONFIG_TARGET)
ifeq ($(CFG_TARGET),platform)
  CFG_TARGET = target
  $(warning Deprecation warning: use CONFIG_TARGET=target instead.)
else ifeq ($(CFG_TARGET),subtarget_platform)
  CFG_TARGET = subtarget_target
  $(warning Deprecation warning: use CONFIG_TARGET=subtarget_target instead.)
endif

# select the config file to be changed by kernel_menuconfig/kernel_oldconfig
ifeq ($(CFG_TARGET),target)
  LINUX_RECONFIG_LIST = $(wildcard $(GENERIC_LINUX_CONFIG) $(LINUX_TARGET_CONFIG))
  LINUX_RECONFIG_TARGET = $(LINUX_TARGET_CONFIG)
else ifeq ($(CFG_TARGET),subtarget)
  LINUX_RECONFIG_LIST = $(wildcard $(GENERIC_LINUX_CONFIG) $(LINUX_TARGET_CONFIG) $(LINUX_SUBTARGET_CONFIG))
  LINUX_RECONFIG_TARGET = $(LINUX_SUBTARGET_CONFIG)
else ifeq ($(CFG_TARGET),subtarget_target)
  LINUX_RECONFIG_LIST = $(wildcard $(GENERIC_LINUX_CONFIG) $(LINUX_SUBTARGET_CONFIG) $(LINUX_TARGET_CONFIG))
  LINUX_RECONFIG_TARGET = $(LINUX_TARGET_CONFIG)
else ifeq ($(CFG_TARGET),env)
  LINUX_RECONFIG_LIST = $(LINUX_KCONFIG_LIST)
  LINUX_RECONFIG_TARGET = $(TOPDIR)/env/kernel-config
else ifneq ($(strip $(CFG_TARGET)),)
  $(error CONFIG_TARGET=$(CFG_TARGET) is invalid. Valid: target|subtarget|subtarget_target|env)
endif

__linux_confcmd = $(2) $(patsubst %,+,$(wordlist 2,9999,$(1))) $(1)

LINUX_CONF_CMD = $(SCRIPT_DIR)/kconfig.pl $(call __linux_confcmd,$(LINUX_KCONFIG_LIST))
LINUX_RECONF_CMD = $(SCRIPT_DIR)/kconfig.pl $(call __linux_confcmd,$(LINUX_RECONFIG_LIST))
LINUX_RECONF_DIFF = $(SCRIPT_DIR)/kconfig.pl - '>' $(call __linux_confcmd,$(filter-out $(LINUX_RECONFIG_TARGET),$(LINUX_RECONFIG_LIST))) $(1) $(GENERIC_PLATFORM_DIR)/config-filter

ifeq ($(DUMP),1)
  BuildTarget=$(BuildTargets/DumpCurrent)

  CPU_CFLAGS = -Os -pipe
  ifneq ($(findstring mips,$(ARCH)),)
    ifneq ($(findstring mips64,$(ARCH)),)
      CPU_TYPE ?= mips64
    else
      CPU_TYPE ?= mips32
    endif
    CPU_CFLAGS += -mno-branch-likely
    CPU_CFLAGS_mips32 = -mips32 -mtune=mips32
    CPU_CFLAGS_mips64 = -mips64 -mtune=mips64 -mabi=64
    CPU_CFLAGS_mips64r2 = -mips64r2 -mtune=mips64r2 -mabi=64
    CPU_CFLAGS_4kec = -mips32r2 -mtune=4kec
    CPU_CFLAGS_24kc = -mips32r2 -mtune=24kc
    CPU_CFLAGS_74kc = -mips32r2 -mtune=74kc
    CPU_CFLAGS_octeonplus = -march=octeon+ -mabi=64
  endif
  ifeq ($(ARCH),i386)
    CPU_TYPE ?= pentium-mmx
    CPU_CFLAGS_pentium-mmx = -march=pentium-mmx
    CPU_CFLAGS_pentium4 = -march=pentium4
  endif
  ifneq ($(findstring arm,$(ARCH)),)
    CPU_TYPE ?= xscale
  endif
  ifeq ($(ARCH),powerpc)
    CPU_CFLAGS_603e:=-mcpu=603e
    CPU_CFLAGS_8540:=-mcpu=8540
    CPU_CFLAGS_8548:=-mcpu=8548
    CPU_CFLAGS_405:=-mcpu=405
    CPU_CFLAGS_440:=-mcpu=440
    CPU_CFLAGS_464fp:=-mcpu=464fp
  endif
  ifeq ($(ARCH),powerpc64)
    CPU_TYPE ?= powerpc64
    CPU_CFLAGS_e5500:=-mcpu=e5500
    CPU_CFLAGS_powerpc64:=-mcpu=powerpc64
  endif
  ifeq ($(ARCH),sparc)
    CPU_TYPE = sparc
    CPU_CFLAGS_ultrasparc = -mcpu=ultrasparc
  endif
  ifeq ($(ARCH),aarch64)
    CPU_TYPE ?= generic
    CPU_CFLAGS_generic = -mcpu=generic
    CPU_CFLAGS_cortex-a53 = -mcpu=cortex-a53
  endif
  ifeq ($(ARCH),arc)
    CPU_TYPE ?= arc700
    CPU_CFLAGS += -matomic
    CPU_CFLAGS_arc700 = -mcpu=arc700
    CPU_CFLAGS_archs = -mcpu=archs
  endif
  ifeq ($(ARCH),riscv64)
    CPU_TYPE ?= generic
    CPU_CFLAGS_generic:=-mabi=lp64d -march=rv64gc
  endif
  ifeq ($(ARCH),loongarch64)
    CPU_TYPE ?= generic
    CPU_CFLAGS := -O2 -pipe
    CPU_CFLAGS_generic:=-march=loongarch64
  endif
  ifneq ($(CPU_TYPE),)
    ifndef CPU_CFLAGS_$(CPU_TYPE)
      $(warning CPU_TYPE "$(CPU_TYPE)" doesn't correspond to a known type)
    endif
  endif
  DEFAULT_CFLAGS=$(strip $(CPU_CFLAGS) $(CPU_CFLAGS_$(CPU_TYPE)) $(CPU_CFLAGS_$(CPU_SUBTYPE)))

  ifneq ($(BOARD),)
    TMP_CONFIG:=$(TMP_DIR)/.kconfig-$(call target_conf,$(TARGETID))
    $(TMP_CONFIG): $(LINUX_KCONFIG_LIST)
		$(LINUX_CONF_CMD) > $@ || rm -f $@
    -include $(TMP_CONFIG)
    .SILENT: $(TMP_CONFIG)
    .PRECIOUS: $(TMP_CONFIG)

    ifdef KERNEL_TESTING_PATCHVER
      ifneq ($(KERNEL_TESTING_PATCHVER),$(KERNEL_PATCHVER))
        FEATURES += testing-kernel
      endif
    endif
    ifneq ($(CONFIG_OF),)
      FEATURES += dt
    endif
    ifneq ($(CONFIG_GENERIC_GPIO)$(CONFIG_GPIOLIB),)
      FEATURES += gpio
    endif
    ifneq ($(CONFIG_PCI),)
      FEATURES += pci
    endif
    ifneq ($(CONFIG_PCIEPORTBUS),)
      FEATURES += pcie
    endif
    ifneq ($(CONFIG_PWM),)
      FEATURES += pwm
    endif
    ifneq ($(CONFIG_USB)$(CONFIG_USB_SUPPORT),)
      ifneq ($(CONFIG_USB_ARCH_HAS_HCD)$(CONFIG_USB_EHCI_HCD),)
        FEATURES += usb
      endif
    endif
    ifneq ($(CONFIG_PCMCIA)$(CONFIG_PCCARD),)
      FEATURES += pcmcia
    endif
    ifneq ($(CONFIG_VGA_CONSOLE)$(CONFIG_FB),)
      FEATURES += display
    endif
    ifneq ($(CONFIG_RTC_CLASS),)
      FEATURES += rtc
    endif
    ifneq ($(CONFIG_VIRTIO),)
      FEATURES += virtio
    endif
    ifneq ($(CONFIG_CPU_MIPS32_R2),)
      FEATURES += mips16
    endif
    ifneq ($(CONFIG_CPU_V6),)
      FEATURES += arm_v6
    endif
    ifneq ($(CONFIG_CPU_V6K),)
      FEATURES += arm_v6
    endif
    ifneq ($(CONFIG_CPU_V7),)
      FEATURES += arm_v7
    endif

    # remove duplicates
    FEATURES:=$(sort $(FEATURES))
  endif
endif

CUR_SUBTARGET:=$(SUBTARGET)
ifeq ($(SUBTARGETS),)
  CUR_SUBTARGET := default
endif

define BuildTargets/DumpCurrent
  .PHONY: dumpinfo
  dumpinfo : export DESCRIPTION=$$(Target/Description)
  dumpinfo:
	@echo 'Target: $(TARGETID)'; \
	 echo 'Target-Board: $(BOARD)'; \
	 echo 'Target-Name: $(BOARDNAME)$(if $(SUBTARGETS),$(if $(SUBTARGET),))'; \
	 echo 'Target-Arch: $(ARCH)'; \
	 echo 'Target-Arch-Packages: $(if $(ARCH_PACKAGES),$(ARCH_PACKAGES),$(ARCH)$(if $(CPU_TYPE),_$(CPU_TYPE))$(if $(CPU_SUBTYPE),_$(CPU_SUBTYPE)))'; \
	 echo 'Target-Features: $(FEATURES)'; \
	 echo 'Target-Depends: $(DEPENDS)'; \
	 echo 'Target-Optimization: $(if $(CFLAGS),$(CFLAGS),$(DEFAULT_CFLAGS))'; \
	 echo 'CPU-Type: $(CPU_TYPE)$(if $(CPU_SUBTYPE),+$(CPU_SUBTYPE))'; \
	 echo 'Linux-Version: $(LINUX_VERSION)'; \
	$(if $(LINUX_TESTING_VERSION),echo 'Linux-Testing-Version: $(LINUX_TESTING_VERSION)';) \
	 echo 'Linux-Release: $(LINUX_RELEASE)'; \
	 echo 'Linux-Kernel-Arch: $(LINUX_KARCH)'; \
	$(if $(SUBTARGET),,$(if $(DEFAULT_SUBTARGET), echo 'Default-Subtarget: $(DEFAULT_SUBTARGET)'; )) \
	 echo 'Target-Description:'; \
	 echo "$$$$DESCRIPTION"; \
	 echo '@@'; \
	 $(if $(DEFAULT_PROFILE),echo 'Target-Default-Profile: $(DEFAULT_PROFILE)';) \
	 echo 'Default-Packages: $(DEFAULT_PACKAGES) $(call extra_packages,$(DEFAULT_PACKAGES))'; \
	 $(DUMPINFO)
	$(if $(CUR_SUBTARGET),$(SUBMAKE) -r --no-print-directory -C image -s DUMP=1 SUBTARGET=$(CUR_SUBTARGET))
	$(if $(SUBTARGET),,@$(foreach SUBTARGET,$(SUBTARGETS),$(SUBMAKE) -s DUMP=1 SUBTARGET=$(SUBTARGET); ))
endef

include $(INCLUDE_DIR)/kernel.mk
ifeq ($(TARGET_BUILD),1)
  include $(INCLUDE_DIR)/kernel-build.mk
  BuildTarget?=$(BuildKernel)
endif

endif #__target_inc
