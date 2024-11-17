# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2007-2020 OpenWrt.org

# define a dependency on a subtree
# parameters:
#	1: directories/files
#	2: directory dependency
#	3: tempfile for file listings
#	4: find options

DEP_FINDPARAMS := -x "*/.svn*" -x ".*" -x "*:*" -x "*\!*" -x "* *" -x "*\\\#*" -x "*/.*_check" -x "*/.*.swp" -x "*/.pkgdir*"

# wildcard 用来匹配文件列表，类似 glob
find_md5=find $(wildcard $(1)) -type f $(patsubst -x,-and -not -path,$(DEP_FINDPARAMS) $(2)) -printf "%p%T@\n" | sort | $(MKHASH) md5
find_md5_reproducible=find $(wildcard $(1)) -type f $(patsubst -x,-and -not -path,$(DEP_FINDPARAMS) $(2)) -print0 | xargs -0 $(MKHASH) md5 | sort | $(MKHASH) md5

define rdep
  # 在发生错误或者信号时，也不要把 $(2) 删除，保护中间文件不被自动删除，确保构建过程的稳定性
  .PRECIOUS: $(2)
  # 在执行 $(2)_check 时，不显示命令本身，精简输出
  .SILENT: $(2)_check

  # 声明依赖关系，$(2) 依赖 $(2)_check
  $(2): $(2)_check
  check-depends: $(2)_check

ifneq ($(wildcard $(2)),)
  $(2)_check::
	$(if $(3), \
		$(call find_md5,$(1),$(4)) > $(3).1; \
		{ [ \! -f "$(3)" ] || diff $(3) $(3).1 >/dev/null; } && \
	) \
	{ \
		[ -f "$(2)_check.1" ] && mv "$(2)_check.1" "$(2)_check"; \
	    $(TOPDIR)/scripts/timestamp.pl $(DEP_FINDPARAMS) $(4) -n $(2) $(1) && { \
			$(call debug_eval,$(SUBDIR),r,echo "No need to rebuild $(2)";) \
			touch -r "$(2)" "$(2)_check"; \
		} \
	} || { \
		$(call debug_eval,$(SUBDIR),r,echo "Need to rebuild $(2)";) \
		touch "$(2)_check"; \
	}
	$(if $(3), mv $(3).1 $(3))
else
  $(2)_check::
	$(if $(3), rm -f $(3) $(3).1)
	$(call debug_eval,$(SUBDIR),r,echo "Target $(2) not built")
endif

endef

# MAKECMDGOALS 是当前要执行的目标名
# % 表示任意个匹配，即任意个 . 开头的字符串，简单的点
# $(if condition,then-part,else-part)：这是 Makefile 中的条件函数。如果 condition 非空，它返回 then-part，否则返回 else-part
ifeq ($(filter .%,$(MAKECMDGOALS)),$(if $(MAKECMDGOALS),$(MAKECMDGOALS),x))
  define rdep
    $(2): $(2)_check
  endef
endif
