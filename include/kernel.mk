# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2006-2020 OpenWrt.org

# 目标是否包含check
ifneq ($(filter check,$(MAKECMDGOALS)),)
CHECK:=1
DUMP:=1
endif

# 让内核相关时间字段稳定，从而提高构建的可复现性
# 当 SOURCE_DATE_EPOCH 已设置，且未处于 DUMP 模式时，Makefile 会把 KBUILD_BUILD_TIMESTAMP 设为该时间对应的 UTC 文本
# 这会影响内核版本字符串（uname -v）以及可能嵌入到内核/模块中的时间信息，从而实现可复现。
ifneq ($(SOURCE_DATE_EPOCH),)
  # DUMP 时跳过，避免在纯解析阶段触发时间相关副作用或执行外部命令
  ifndef DUMP
    # 使用Perl脚本将 SOURCE_DATE_EPOCH 转换为GMT时间戳
    KBUILD_BUILD_TIMESTAMP:=$(shell perl -e 'print scalar gmtime($(SOURCE_DATE_EPOCH))')
  endif
endif

# 如果__target_inc未定义，并且 CHECK 未定义，则包含 target.mk 文件
# __target_inc 是 target.mk 的哨兵变量，重复包含。为空表示 target.mk 还没有被包含过
ifeq ($(__target_inc),)
  # 跳过 heavy include：在 make check / DUMP 模式下只做语法/元数据检查，不需要也不应依赖完整的目标配置与工具链环境；强行包含 target.mk 可能会因为缺少 .config 或环境未准备好而报错或变慢
  ifndef CHECK
    include $(INCLUDE_DIR)/target.mk
  endif
endif

ifeq ($(DUMP),1)
  # 设置一些默认变量，保证在环境未完整（无 .config、无 kernel tree）的情况下仍能导出包元数据
  # make 系统不会自动将 KERNEL 替换为真正的值，这里是简单的原始字符串，需要用户自己覆盖变量
  KERNEL?=<KERNEL>
  BOARD?=<BOARD>
  LINUX_VERSION?=<LINUX_VERSION>
  LINUX_VERMAGIC?=<LINUX_VERMAGIC>
else
  ifeq ($(CONFIG_EXTERNAL_TOOLCHAIN),)
    # 约束编译器 honor 选项的行为，避免包/环境里的非常规 CFLAGS 污染内核/模块构建（与 Kbuild 期望冲突会引发奇怪问题）
    export GCC_HONOUR_COPTS=s
  endif

  # 明确模块后缀，便于安装/匹配
  LINUX_KMOD_SUFFIX=ko

  # UML 用宿主编译器，其余用目标工具链；原因是 UML 在用户态模拟，更像 host 构建
  ifneq (,$(findstring uml,$(BOARD)))
    KERNEL_CC?=$(HOSTCC)
    KERNEL_CROSS?=
  else
    KERNEL_CC?=$(TARGET_CC)
    KERNEL_CROSS?=$(TARGET_CROSS)
  endif

  # 根据 KERNEL_PATCHVER 选择补丁和 files 目录；不同内核小版本需要不同补丁/文件。
  ifeq ($(TARGET_BUILD),1)
    PATCH_DIR ?= $(CURDIR)/patches$(if $(wildcard ./patches-$(KERNEL_PATCHVER)),-$(KERNEL_PATCHVER))
    FILES_DIR ?= $(foreach dir,$(wildcard $(CURDIR)/files $(CURDIR)/files-$(KERNEL_PATCHVER)),"$(dir)")
  endif
  # 标准化构建输出位置；多目标/多内核版本并行构建时避免冲突
  KERNEL_BUILD_DIR ?= $(BUILD_DIR)/linux-$(BOARD)_$(SUBTARGET)
  LINUX_DIR ?= $(KERNEL_BUILD_DIR)/linux-$(LINUX_VERSION)
  LINUX_UAPI_DIR=uapi/
  # 读取 LINUX_VERMAGIC（.vermagic）并兜底 unknown：用于 pin 住 ABI，防止不同 ABI 的模块被安装
  LINUX_VERMAGIC:=$(strip $(shell cat $(LINUX_DIR)/.vermagic 2>/dev/null))
  LINUX_VERMAGIC:=$(if $(LINUX_VERMAGIC),$(LINUX_VERMAGIC),unknown)

  # LINUX_UNAME_VERSION 衍生 rc 后缀：匹配内核的实际 uname 版本，确保模块安装路径 lib/modules/ 正确
  LINUX_UNAME_VERSION:=$(KERNEL_BASE)
  ifneq ($(findstring -rc,$(LINUX_VERSION)),)
    LINUX_UNAME_VERSION:=$(LINUX_UNAME_VERSION)-$(strip $(lastword $(subst -, ,$(LINUX_VERSION))))
  endif

  LINUX_KERNEL:=$(KERNEL_BUILD_DIR)/vmlinux

  # rc 版本通常为 .tar.gz
  ifneq (,$(findstring -rc,$(LINUX_VERSION)))
      LINUX_SOURCE:=linux-$(LINUX_VERSION).tar.gz
  else
      LINUX_SOURCE:=linux-$(LINUX_VERSION).tar.xz
  endif

  # 兼容多种内核来源，保证获取到正确的源码与版本标识
  # rc 版本使用 torvalds 快照源
  ifneq (,$(findstring -rc,$(LINUX_VERSION)))
      LINUX_SITE:=https://git.kernel.org/torvalds/t
  # 非 rc 且无外部内核树/仓库时，使用 kernel.org 的主线/稳定版本路径
  else ifeq ($(call qstrip,$(CONFIG_EXTERNAL_KERNEL_TREE))$(call qstrip,$(CONFIG_KERNEL_GIT_CLONE_URI)),)
      LINUX_SITE:=@KERNEL/linux/kernel/v$(word 1,$(subst ., ,$(KERNEL_BASE))).x
  # 使用外部内核树/仓库时，从 kernel.release 读取真实版本
  else
      LINUX_UNAME_VERSION:=$(strip $(shell cat $(LINUX_DIR)/include/config/kernel.release 2>/dev/null))
  endif

  # 设定模块安装目录；内核模块的标准布局
  MODULES_SUBDIR:=lib/modules/$(LINUX_UNAME_VERSION)
  TARGET_MODULES_DIR:=$(LINUX_TARGET_DIR)/$(MODULES_SUBDIR)

  # 非 TARGET_BUILD 情况下设置 PKG_BUILD_DIR：SDK/单包构建时给外部模块一个稳定的构建目录
  ifneq ($(TARGET_BUILD),1)
    PKG_BUILD_DIR ?= $(KERNEL_BUILD_DIR)/$(if $(BUILD_VARIANT),$(PKG_NAME)-$(BUILD_VARIANT)/)$(PKG_NAME)$(if $(PKG_VERSION),-$(PKG_VERSION))
  endif
endif

# LINUX_KARCH 决策
# 将 OpenWrt ARCH 名称映射为内核的 Kbuild ARCH（如 aarch64→arm64、i386/x86_64→x86 等）
# 原因：Kbuild 的 ARCH 集合与用户空间架构名不完全一致，必须映射才能正确编译
ifneq (,$(findstring uml,$(BOARD)))
  LINUX_KARCH=um
else ifneq (,$(findstring $(ARCH) , aarch64 aarch64_be ))
  LINUX_KARCH := arm64
else ifneq (,$(findstring $(ARCH) , arceb ))
  LINUX_KARCH := arc
else ifneq (,$(findstring $(ARCH) , armeb ))
  LINUX_KARCH := arm
else ifneq (,$(findstring $(ARCH) , loongarch64 ))
  LINUX_KARCH := loongarch
else ifneq (,$(findstring $(ARCH) , mipsel mips64 mips64el ))
  LINUX_KARCH := mips
else ifneq (,$(findstring $(ARCH) , powerpc64 ))
  LINUX_KARCH := powerpc
else ifneq (,$(findstring $(ARCH) , riscv64 ))
  LINUX_KARCH := riscv
else ifneq (,$(findstring $(ARCH) , sh2 sh3 sh4 ))
  LINUX_KARCH := sh
else ifneq (,$(findstring $(ARCH) , i386 x86_64 ))
  LINUX_KARCH := x86
else
  LINUX_KARCH := $(ARCH)
endif

# 内核构架命令
KERNEL_MAKE = $(MAKE) $(KERNEL_MAKEOPTS)

KERNEL_MAKE_FLAGS = \
  # 注入 iremap 的路径重写（将绝对路径映射为相对/简短路径，利于可复现），拼接 OpenWrt/Kernel 额外 CFLAGS，并过滤掉不适合 Kernel 构建的标志（如 -fno-plt），避免与 Kbuild 选项冲突
	KCFLAGS="$(call iremap,$(BUILD_DIR),$(notdir $(BUILD_DIR))) $(filter-out -fno-plt,$(call qstrip,$(CONFIG_EXTRA_OPTIMIZATION))) $(call qstrip,$(CONFIG_KERNEL_CFLAGS))" \
  # 为内核构建时的宿主工具提供更严格的告警选项
	HOSTCFLAGS="$(HOST_CFLAGS) -Wall -Wmissing-prototypes -Wstrict-prototypes" \
  # 指定交叉编译前缀与架构，确保使用目标工具链
	CROSS_COMPILE="$(KERNEL_CROSS)" \
	ARCH="$(LINUX_KARCH)" \
  # 禁止 NLS，减少构建差异与依赖
	KBUILD_HAVE_NLS=no \
  # 设置构建用户/主机/时间戳，版本固定为 0
  # 降低非功能性变更（用户名、主机名、构建次数）对产物哈希的影响，提升可复现性
	KBUILD_BUILD_USER="$(call qstrip,$(CONFIG_KERNEL_BUILD_USER))" \
	KBUILD_BUILD_HOST="$(call qstrip,$(CONFIG_KERNEL_BUILD_DOMAIN))" \
	KBUILD_BUILD_TIMESTAMP="$(KBUILD_BUILD_TIMESTAMP)" \
	KBUILD_BUILD_VERSION="0" \
  # 指向主机库路径，避免链接宿主工具时找不到依赖
	KBUILD_HOSTLDFLAGS="-L$(STAGING_DIR_HOST)/lib" \
  # 指定 Bash，减少不同默认 shell 带来的行为差异
	CONFIG_SHELL="$(BASH)" \
  # 根据 OPENWRT_VERBOSE 控制构建时的详细输出
	$(if $(findstring c,$(OPENWRT_VERBOSE)),V=1,V='') \
  # 若指定 PKG_BUILD_ID，为模块注入可控 build-id，便于追溯且保持一致性
	$(if $(PKG_BUILD_ID),LDFLAGS_MODULE=--build-id=0x$(PKG_BUILD_ID)) \
  # 清空生成 syscall 表的命令，避免在外部模块构建中触发不必要的 header 生成/依赖（加快速度，减少对宿主工具链脚本的要求）
	cmd_syscalls= \
  # 把其他包导出的 symvers 文件交给 Kbuild，解决分拆包间的符号版本解析问题
	$(if $(__package_mk),KBUILD_EXTRA_SYMBOLS="$(wildcard $(PKG_SYMVERS_DIR)/*.symvers)")

# 若 KERNEL_CC 非空则显式覆盖 CC；原因：UML 或特殊需求时使用宿主 CC
ifneq (,$(KERNEL_CC))
  KERNEL_MAKE_FLAGS += CC="$(KERNEL_CC)"
endif

# 确保使用正确的工具链头文件路径，并在 DUMP 中避免调用编译器
KERNEL_NOSTDINC_FLAGS = \
  # 始终 -nostdinc，避免误用宿主头文件
  # 非 DUMP 时再补上 -isystem $(TARGET_CC -print-file-name=include)，指向交叉工具链内置头
  # DUMP 下省略外部命令调用以保持纯解析
	-nostdinc $(if $(DUMP),, -isystem $(shell $(TARGET_CC) -print-file-name=include))

# 当未使用外部内核树/仓库时，明确 KERNELRELEASE=$(LINUX_VERSION)
# 给外部模块构建提供稳定的内核版本标识，影响 vermagic 与安装路径；外部内核树自带定义时不强行覆盖
ifeq ($(call qstrip,$(CONFIG_EXTERNAL_KERNEL_TREE))$(call qstrip,$(CONFIG_KERNEL_GIT_CLONE_URI)),)
  KERNEL_MAKE_FLAGS += \
	KERNELRELEASE=$(LINUX_VERSION)
endif

# 非 Linux 主机上关闭 CONFIG_STACK_VALIDATION 并导出 SKIP_STACK_VALIDATION=1
# objtool 等验证器在非 Linux 环境不稳定或不可用，强开会失败
ifneq ($(HOST_OS),Linux)
  KERNEL_MAKE_FLAGS += CONFIG_STACK_VALIDATION=
  export SKIP_STACK_VALIDATION:=1
endif

KERNEL_MAKEOPTS = -C $(LINUX_DIR) $(KERNEL_MAKE_FLAGS)

# 开启 CONFIG_USE_SPARSE 时在 Kbuild 上传 C=1 和 sparse 路径
# 可选的内核代码静态分析，便于发现类型/内存模型问题
ifdef CONFIG_USE_SPARSE
  KERNEL_MAKEOPTS += C=1 CHECK=$(STAGING_DIR_HOST)/bin/sparse
endif

PKG_EXTMOD_SUBDIRS ?= .

PKG_SYMVERS_DIR = $(KERNEL_BUILD_DIR)/symvers

# 收集模块的符号版本信息，从各子目录的 Module.symvers 聚合、去重，存到 $(PKG_SYMVERS_DIR)/$(PKG_NAME).symvers
# 外部模块常依赖其他 kmod 导出的符号，聚合 symvers 便于后续包解析与链接
define collect_module_symvers
	for subdir in $(PKG_EXTMOD_SUBDIRS); do \
		realdir=$$$$(readlink -f $(PKG_BUILD_DIR)); \
		grep -F $(PKG_BUILD_DIR) $(PKG_BUILD_DIR)/$$$$subdir/Module.symvers >> $(PKG_BUILD_DIR)/Module.symvers.tmp; \
		[ "$(PKG_BUILD_DIR)" = "$$$$realdir" ] || \
			grep -F $$$$realdir $(PKG_BUILD_DIR)/$$$$subdir/Module.symvers >> $(PKG_BUILD_DIR)/Module.symvers.tmp; \
	done; \
	sort -u $(PKG_BUILD_DIR)/Module.symvers.tmp > $(PKG_BUILD_DIR)/Module.symvers; \
	mkdir -p $(PKG_SYMVERS_DIR); \
	mv $(PKG_BUILD_DIR)/Module.symvers $(PKG_SYMVERS_DIR)/$(PKG_NAME).symvers
endef

# 非内核本体包在编译后挂接 collect_module_symvers
# 自动化地把符号版本导出到集中位置，供其他包使用
define KernelPackage/hooks
  ifneq ($(PKG_NAME),kernel)
    Hooks/Compile/Post += collect_module_symvers
  endif
  define KernelPackage/hooks
  endef
endef

# 为 kmod 包提供统一、可覆盖的默认行为；nonshared 表示包不会在 SDK 间共享
define KernelPackage/Defaults
  FILES:=
  AUTOLOAD:=
  MODPARAMS:=
  PKGFLAGS+=nonshared
endef

# 生成 /etc/modules.d 和可选的 /etc/modules-boot.d 条目，注入模块加载顺序与参数
# 用包元数据驱动系统启动时自动加载模块，减少手动配置。
# 1: name
# 2: install prefix
# 3: module priority prefix
# 4: required for boot
# 5: module list
define ModuleAutoLoad
  $(if $(5), \
    mkdir -p $(2)/etc/modules.d; \
    ($(foreach mod,$(5), \
      echo "$(mod)$(if $(MODPARAMS.$(mod)), $(MODPARAMS.$(mod)),$(if $(MODPARAMS), $(MODPARAMS)))"; )) > $(2)/etc/modules.d/$(3)$(1); \
    $(if $(4), \
      mkdir -p $(2)/etc/modules-boot.d; \
      ln -sf ../modules.d/$(3)$(1) $(2)/etc/modules-boot.d/;))
endef

# 在既不是 DUMP、也不是 TARGET_BUILD 的情况下尝试包含 $(LINUX_DIR)/.config
# 在某些构建阶段需要读取内核配置以决定条件编译/依赖；DUMP 时不需要，TARGET_BUILD 场景下由其他步骤负责
ifeq ($(DUMP)$(TARGET_BUILD),)
  -include $(LINUX_DIR)/.config
endif

# 当内核配置变化时，触发相关包重建，避免 ABI 或配置不匹配
define KernelPackage/depends
  $(STAMP_BUILT): $(LINUX_DIR)/.config
  define KernelPackage/depends
  endef
endef

# 用于创建内核包。包括包的名称、标题、描述、依赖等。
define KernelPackage
  NAME:=$(1)
  $(eval $(call Package/Default))
  $(eval $(call KernelPackage/Defaults))
  $(eval $(call KernelPackage/$(1)))
  $(eval $(call KernelPackage/$(1)/$(BOARD)))
  $(eval $(call KernelPackage/$(1)/$(BOARD)/$(SUBTARGET)))

  define Package/kmod-$(1)
    TITLE:=$(TITLE)
    SECTION:=kernel
    CATEGORY:=Kernel modules
    DESCRIPTION:=$(DESCRIPTION)
    # 将内核版本与 vermagic、release 精确绑定，例如 kernel (=<LINUX_VERSION>~-r)
    # 强制 opkg 等包管理器拒绝安装 ABI 不匹配的模块
    EXTRA_DEPENDS:=kernel (=$(LINUX_VERSION)~$(LINUX_VERMAGIC)-r$(LINUX_RELEASE))
    VERSION:=$(LINUX_VERSION)$(if $(PKG_VERSION),.$(PKG_VERSION))-r$(if $(PKG_RELEASE),$(PKG_RELEASE),$(LINUX_RELEASE))
    PKGFLAGS:=$(PKGFLAGS)
    $(call KernelPackage/$(1))
    $(call KernelPackage/$(1)/$(BOARD))
    $(call KernelPackage/$(1)/$(BOARD)/$(SUBTARGET))
  endef

  ifdef KernelPackage/$(1)/conffiles
    define Package/kmod-$(1)/conffiles
$(call KernelPackage/$(1)/conffiles)
    endef
  endif

  ifdef KernelPackage/$(1)/description
    define Package/kmod-$(1)/description
$(call KernelPackage/$(1)/description)
    endef
  endif

  ifdef KernelPackage/$(1)/config
    define Package/kmod-$(1)/config
$(call KernelPackage/$(1)/config)
    endef
  endif

  $(call KernelPackage/depends)
  $(call KernelPackage/hooks)

  ifneq ($(if $(filter-out %=y %=n %=m,$(KCONFIG)),$(filter m y,$(foreach c,$(call version_filter,$(filter-out %=y %=n %=m,$(KCONFIG))),$($(c)))),.),)
    define Package/kmod-$(1)/install
		  @for mod in $$(call version_filter,$$(FILES)); do \
      # 检查 modules.builtin，内建模块不再打包
			if grep -q "$$$$$$$${mod##$(LINUX_DIR)/}" "$(LINUX_DIR)/modules.builtin"; then \
				echo "NOTICE: module '$$$$$$$$mod' is built-in."; \
      # 复制 .ko 到 lib/modules/<uname_ver>
			elif [ -e $$$$$$$$mod ]; then \
				mkdir -p $$(1)/$(MODULES_SUBDIR) ; \
				$(CP) -L $$$$$$$$mod $$(1)/$(MODULES_SUBDIR)/ ; \
			else \
				echo "ERROR: module '$$$$$$$$mod' is missing." >&2; \
				exit 1; \
			fi; \
		  done;
      # 生成自动加载条目
		  $(call ModuleAutoLoad,$(1),$$(1),$(filter-out 0-,$(word 1,$(AUTOLOAD))-),$(filter-out 0,$(word 2,$(AUTOLOAD))),$(sort $(wordlist 3,99,$(AUTOLOAD))))
      # 允许每个包自定义安装逻辑
		  $(call KernelPackage/$(1)/install,$$(1))
    endef
    # 若 Kconfig 未启用该模块：生成“空包”并给出 WARNING。 原因：保持包索引完整、依赖可解，同时不产生实际内容
  $(if $(CONFIG_PACKAGE_kmod-$(1)),
    else
      compile: $(1)-disabled
      $(1)-disabled:
		@echo "WARNING: kmod-$(1) is not available in the kernel config - generating empty package" >&2

      define Package/kmod-$(1)/install
		true
      endef
  )
  endif
  # 最终调用 BuildPackage 构建 ipk，并声明打包依赖于匹配版本的文件清单
  $$(eval $$(call BuildPackage,kmod-$(1)))

  $$(IPKG_kmod-$(1)): $$(wildcard $$(call version_filter,$$(FILES)))

endef

# 当文件列表带有 @ 条件时，调用脚本按 KERNEL_PATCHVER 过滤合适版本的文件
version_filter=$(if $(findstring @,$(1)),$(shell $(SCRIPT_DIR)/package-metadata.pl version_filter $(KERNEL_PATCHVER) $(1)),$(1))

# 包装优先级、是否开机加载，并走 version_filter
# 同一模块在不同内核小版本可能文件名/位置不同，需要按版本条件选择；同时统一生成自动加载配置
# 1: priority (optional)
# 2: module list
# 3: boot flag
define AutoLoad
  $(if $(1),$(1),0) $(if $(3),1,0) $(call version_filter,$(2))
endef

# 1: module list
# 2: boot flag
define AutoProbe
  $(call AutoLoad,,$(1),$(2))
endef

version_field=$(if $(word $(1),$(2)),$(word $(1),$(2)),0)
kernel_version_merge=$$(( ($(call version_field,1,$(1)) << 24) + ($(call version_field,2,$(1)) << 16) + ($(call version_field,3,$(1)) << 8) + $(call version_field,4,$(1)) ))

# DUMP 阶段不比较可减少外部依赖和不确定性
ifdef DUMP
  kernel_version_cmp=
else
  kernel_version_cmp=$(shell [ $(call kernel_version_merge,$(call split_version,$(2))) $(1) $(call kernel_version_merge,$(call split_version,$(3))) ] && echo 1 )
endif

# 比较内核版本号，用于在 Makefile 中做条件判断
# 在纯 Make 环境中没有天然的版本比较，需要自定义
CompareKernelPatchVer=$(if $(call kernel_version_cmp,-$(2),$(1),$(3)),1,0)

kernel_patchver_gt=$(call kernel_version_cmp,-gt,$(KERNEL_PATCHVER),$(1))
kernel_patchver_ge=$(call kernel_version_cmp,-ge,$(KERNEL_PATCHVER),$(1))
kernel_patchver_eq=$(call kernel_version_cmp,-eq,$(KERNEL_PATCHVER),$(1))
kernel_patchver_le=$(call kernel_version_cmp,-le,$(KERNEL_PATCHVER),$(1))
kernel_patchver_lt=$(call kernel_version_cmp,-lt,$(KERNEL_PATCHVER),$(1))

