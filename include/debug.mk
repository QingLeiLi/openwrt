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

ifeq ($(DUMP),)
  ifeq ($(DEBUG),all)
    build_debug:=dltvr
  else
    build_debug:=$(DEBUG)
  endif
endif

ifneq ($(DEBUG),)

define debug
# make中 $ 用于引用变量，如果需要原始的 $，则用 $$ 表示
$$(findstring $(2),$$(if $$(DEBUG_SCOPE_DIR),$$(if $$(filter $$(DEBUG_SCOPE_DIR)%,$(1)),$(build_debug)),$(build_debug)))
endef

define warn
$$(if $(call debug,$(1),$(2)),$$(warning $(3)))
endef

define debug_eval
$$(if $(call debug,$(1),$(2)),$(3))
endef

define warn_eval
$(call warn,$(1),$(2),$(3)	$(4))
$(4)
endef

else

debug:=
warn:=
debug_eval:=
warn_eval = $(4)

endif

