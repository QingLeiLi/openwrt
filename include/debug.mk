# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2007-2020 OpenWrt.org

# debug flags:
#
# d: show subdirectory tree
# t: show added targets
# l: show legacy targets
# r: show autorebuild messages
# v: verbose (no .SILENCE for common targets)

# 定义了几个 debug 用的宏

# build_debug 是日志级别，调用 debug 的时候会传递当前日志的级别，需要在 build_debug 中包含这个级别才会输出
ifeq ($(DUMP),)
  # 别名，包含所有的日志级别：d、l、t、v、r
  ifeq ($(DEBUG),all)
    # 可能是 debug、log、trace、verbose、report
    build_debug:=dltvr
  else
    build_debug:=$(DEBUG)
  endif
endif

ifneq ($(DEBUG),)

# 这个函数根据 DEBUG_SCOPE_DIR 和 build_debug 来判断是否需要输出，返回是boolean值
# 参数1：文件路径，用于判断是否在 DEBUG_SCOPE_DIR 下，不在则不输出
# 参数2：debug级别，用于跟 build_debug 匹配，如果 build_debug 不包含对应的级别，则不输出
# 否则，输出
define debug
# make中 $ 用于引用变量，如果需要原始的 $，则用 $$ 表示
# $2 是日志级别，需要包含在后面返回中
$$(findstring $(2), $$(
  # 下面这段是通过 DEBUG_SCOPE_DIR 来输出日志级别列表
  # 如果 DEBUG_SCOPE_DIR 没定义，直接返回 build_debug
  # 如果定义了，则文件所在路径需要以 DEBUG_SCOPE_DIR 开头
  if $$(DEBUG_SCOPE_DIR),$$(
    if $$(
      # 第一个参数需要以 $(DEBUG_SCOPE_DIR) 开头
      filter $$(DEBUG_SCOPE_DIR)%,$(1)
    ),$(build_debug)
  ),$(build_debug)
))
endef

# 使用 debug 判断日志是否需要输出
# 使用 warning 打印警告日志，warning 是 make 的内置函数
define warn
$$(if $(call debug,$(1),$(2)),$$(warning $(3)))
endef

# 使用 debug 判断日志是否需要输出
# 需要输出的话就执行 $3
define debug_eval
$$(if $(call debug,$(1),$(2)),$(3))
endef

# 执行一个命令，这个命令根据warn进行打印
# 命令都会执行，只是是否打印由 warn 控制
define warn_eval
# 第三个参数是将 $(3)和$(4) 中间拼个空格，作为一个整体传给 warn 的
$(call warn,$(1),$(2),$(3)	$(4))
$(4)
endef

else

debug:=
warn:=
debug_eval:=
# 这个是延迟解析，warn_eval 还是作为一个宏调用，只不过直接返回了第四个参数，call的话会直接执行 $(4)
warn_eval = $(4)

endif

