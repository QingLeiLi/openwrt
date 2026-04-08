# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2015-2020 OpenWrt.org

# 采用“全局配置 + 每包可覆盖”的双重门闸，尽可能把安全默认打开，但允许个别包因兼容/性能原因退出
#   CONFIG_PKG_*：来自 menuconfig 的全局开关（比如 CONFIG_PKG_ASLR_PIE_ALL）。只有全局开启时才考虑注入对应的标志。
#   PKG_* 变量：包级默认值（?= 设定默认），包可以在自身 Makefile 里覆盖为 0 以退出。例如 PKG_SSP:=0。

# 格式字符串安全检查
PKG_CHECK_FORMAT_SECURITY ?= 1
# ASLR/PIE（位置无关可执行，配合地址空间随机化）
PKG_ASLR_PIE ?= 1
PKG_ASLR_PIE_REGULAR ?= 0
# 栈保护（Stack Protector）
PKG_SSP ?= 1
# 源代码加固
PKG_FORTIFY_SOURCE ?= 1
# RELRO（只读重定位）与 NOW（急切绑定）
PKG_RELRO ?= 1

# 格式字符串安全检查
# 把潜在的格式化字符串漏洞（如 printf(user_input)）从警告升级为“构建期错误”，强制修复
ifdef CONFIG_PKG_CHECK_FORMAT_SECURITY
  ifeq ($(strip $(PKG_CHECK_FORMAT_SECURITY)),1)
    TARGET_CFLAGS += -Wformat -Werror=format-security
  endif
endif

# ASLR/PIE（位置无关可执行，配合地址空间随机化）
# 开启 PIE（位置无关可执行）后，配合内核 ASLR，程序地址空间随机化更彻底，阻断固定地址利用
# 使用 $(FPIC) 与自定义 specs 文件是为了在不同架构/工具链下稳定地让链接器按 PIE 方式链接（相当于常见的 -fPIE/-pie），并兼容上游构建系统可能覆盖 LDFLAGS 的情况
# REGULAR 与 ALL 的区别：ALL 面向所有包，REGULAR 只对“标记为常规”的包启用（维护者可按包能力渐进启用，减少兼容性回归）
ifdef CONFIG_PKG_ASLR_PIE_ALL
  ifeq ($(strip $(PKG_ASLR_PIE)),1)
    TARGET_CFLAGS += $(FPIC)
    TARGET_LDFLAGS += $(FPIC) -specs=$(INCLUDE_DIR)/hardened-ld-pie.specs
  endif
endif
ifdef CONFIG_PKG_ASLR_PIE_REGULAR
  ifeq ($(strip $(PKG_ASLR_PIE_REGULAR)),1)
    TARGET_CFLAGS += $(FPIC)
    TARGET_LDFLAGS += $(FPIC) -specs=$(INCLUDE_DIR)/hardened-ld-pie.specs
  endif
endif

# 栈保护（Stack Protector）
# 在函数栈帧中放置 canary，检测栈破坏（典型是栈溢出），被篡改即崩溃退出，阻断利用
# 分为三个等级：regular、strong、all
# strong 比 regular 覆盖更多函数，all 最激进（可能有更高性能/兼容开销）
ifdef CONFIG_PKG_CC_STACKPROTECTOR_REGULAR
  ifeq ($(strip $(PKG_SSP)),1)
    TARGET_CFLAGS += -fstack-protector
  endif
endif
ifdef CONFIG_PKG_CC_STACKPROTECTOR_STRONG
  ifeq ($(strip $(PKG_SSP)),1)
    TARGET_CFLAGS += -fstack-protector-strong
  endif
endif
ifdef CONFIG_PKG_CC_STACKPROTECTOR_ALL
  ifeq ($(strip $(PKG_SSP)),1)
    TARGET_CFLAGS += -fstack-protector-all
  endif
endif

# 源代码加固
# 在编译期/运行期对易错 libc 调用（如 strcpy、sprintf 等）做更严格的参数与边界检查
# 等级越高检查越多；通常需要有优化（-O1/-O2 及以上）才能发挥作用
ifdef CONFIG_PKG_FORTIFY_SOURCE_1
  ifeq ($(strip $(PKG_FORTIFY_SOURCE)),1)
    TARGET_CFLAGS += -D_FORTIFY_SOURCE=1
  endif
endif
ifdef CONFIG_PKG_FORTIFY_SOURCE_2
  ifeq ($(strip $(PKG_FORTIFY_SOURCE)),1)
    TARGET_CFLAGS += -D_FORTIFY_SOURCE=2
  endif
endif
ifdef CONFIG_PKG_FORTIFY_SOURCE_3
  ifeq ($(strip $(PKG_FORTIFY_SOURCE)),1)
    TARGET_CFLAGS += -D_FORTIFY_SOURCE=3
  endif
endif

# RELRO（只读重定位）与 NOW（急切绑定）
# RELRO 让包含关键指针的段在加载后变为只读，降低 GOT/DTORS 等被篡改的风险
# FULL 额外加 -z now（禁用 lazy binding，启动阶段即完成符号解析），进一步避免运行时对 GOT 的可写性需求。代价是首启稍慢
# 同时加到 CFLAGS 与 LDFLAGS 的原因：
#   很多上游项目用 $(CC) 完成链接，只识别通过 CFLAGS 传给链接器的 -Wl,xxx 选项
#   也有项目使用 $(LD) 或单独的 LDFLAGS。双处追加能最大程度确保生效
ifdef CONFIG_PKG_RELRO_PARTIAL
  ifeq ($(strip $(PKG_RELRO)),1)
    TARGET_CFLAGS += -Wl,-z,relro
    TARGET_LDFLAGS += -zrelro
  endif
endif
ifdef CONFIG_PKG_RELRO_FULL
  ifeq ($(strip $(PKG_RELRO)),1)
    TARGET_CFLAGS += -Wl,-z,now -Wl,-z,relro
    TARGET_LDFLAGS += -znow -zrelro
  endif
endif

