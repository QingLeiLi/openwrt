# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2006-2020 OpenWrt.org

# 这个应该是处理日志级别的，输出的内容不一样多，主要是 make 的 V 参数

# ws
# w - warnings/errors only
# s - stdout+stderr
# c - commands
ifndef OPENWRT_VERBOSE
  OPENWRT_VERBOSE:=
endif
# $(origin V): 用于获取变量 V 的来源，command line 表示是从命令行传入的
# undefined: 变量未定义。
# default: 变量使用的是 Make 的默认值。
# environment: 变量从环境变量中继承。
# environment override: 变量从环境变量中继承，并且使用 -e 选项强制覆盖。
# file: 变量在 Makefile 中定义。
# command line: 变量从命令行传递。
# override: 变量使用 override 关键字在 Makefile 中定义。
# automatic: 变量是自动变量（如 $@, $<, $^ 等）

# V一般代表 verbosity，指日志的详细程度
ifeq ("$(origin V)", "command line")
  OPENWRT_VERBOSE:=$(V)
endif

ifeq ($(OPENWRT_VERBOSE),1)
  OPENWRT_VERBOSE:=w
endif
ifeq ($(OPENWRT_VERBOSE),99)
  OPENWRT_VERBOSE:=s
endif

# V的 s 肯定跟 trace 相关
ifeq ($(NO_TRACE_MAKE),)
NO_TRACE_MAKE := $(MAKE) V=s$(OPENWRT_VERBOSE)
export NO_TRACE_MAKE
endif

ifeq ($(IS_TTY),1)
  ifneq ($(strip $(NO_COLOR)),1)
    # ANSI 转义序列，用于在终端展示颜色
    # 黄色
    _Y:=\\033[33m
    # 红色
    _R:=\\033[31m
    # 重置颜色
    _N:=\\033[m
  endif
endif

# 输出错误日志，先尝试输出到 文件描述符9，如果失败，再输出到标准错误（stderr）
define ERROR_MESSAGE
  { \
	printf "$(_R)%s$(_N)\n" "$(1)" >&9 || \
	printf "$(_R)%s$(_N)\n" "$(1)"; \
  } >&2 2>/dev/null
endef

ifeq ($(findstring s,$(OPENWRT_VERBOSE)),)
  define MESSAGE
	{ \
		printf "$(_Y)%s$(_N)\n" "$(1)" >&8 || \
		printf "$(_Y)%s$(_N)\n" "$(1)"; \
	} 2>/dev/null
  endef

  ifeq ($(QUIET),1)
    # _DIR是 CURDIR 相对于 TOPDIR 的相对路径，CURDIR 是执行make的目录
    ifneq ($(CURDIR),$(TOPDIR))
      _DIR:=$(patsubst $(TOPDIR)/%,%,${CURDIR})
    else
      _DIR:=
    endif
    # 如果用户在命令行指定了make目标
    _MESSAGE:=$(if $(MAKECMDGOALS),$(shell \
      # 就使用 MESSAGE 将目标信息打印出来
      # MAKELEVEL 是make执行的嵌套层数
		  $(call MESSAGE, make[$(MAKELEVEL)]$(if $(_DIR), -C $(_DIR)) $(MAKECMDGOALS)); \
    ))
    # info 是make的函数，用于标准输出
    ifneq ($(strip $(_MESSAGE)),)
      $(info $(_MESSAGE))
    endif
    SUBMAKE=$(MAKE)
  else
    SILENT:=>/dev/null $(if $(findstring w,$(OPENWRT_VERBOSE)),,2>&1)
    export QUIET:=1
    # cmd() { ... }：定义了一个名为 cmd 的 shell 函数
    # -s 使make处于静默模式
    # $@ 内置变量，传递所有参数
    # 8>&1 和 9>&2：将文件描述符 8 重定向到标准输出，将文件描述符 9 重定向到标准错误
    SUBMAKE=cmd() { $(SILENT) $(MAKE) -s "$$@" < /dev/null || { echo "make $$*: build failed. Please re-run make with -j1 V=s or V=sc for a higher verbosity level to see what's going on"; false; } } 8>&1 9>&2; cmd
  endif

  # 不显示命令
  .SILENT: $(MAKECMDGOALS)
else
  # -w 用于打印目录信息，类似：make: Entering directory '/path/to/project'
  SUBMAKE=$(MAKE) -w
  define MESSAGE
    printf "%s\n" "$(1)"
  endef
endif
