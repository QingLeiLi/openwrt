# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2007-2020 OpenWrt.org

# define a dependency on a subtree
# parameters:
#	1: directories/files
#	2: directory dependency
#	3: tempfile for file listings
#	4: find options

# find命令的公共参数，-x 不是一个合法标识，只是一个占位符，后续会在使用时被替换为 -and -not -path
DEP_FINDPARAMS := -x "*/.svn*" -x ".*" -x "*:*" -x "*\!*" -x "* *" -x "*\\\#*" -x "*/.*_check" -x "*/.*.swp" -x "*/.pkgdir*"

# 第一个参数是 文件夹路径，表示在哪里找文件
# 第二个参数是 文件匹配规则，要找谁
# 整体功能：在 $(1) 文件夹下找到命中 $(2) 的文件，然后对文件名和修改时间戳计算md5

# wildcard 用来匹配文件列表，类似 glob，将文件夹中文件都罗列出来
# find 命令用来查找文件，-type f 表示只查找文件，-printf 也是find的参数，"%p%T@\n" 表示输出文件名和修改时间（秒级时间戳）
# $(patsubst -x,-and -not -path,$(DEP_FINDPARAMS) $(2))：将 -x 替换为find的参数 -and -not -path，-x在上面定义只是一个占位符，不是合法标识
# $(MKHASH) md5 用来计算 md5 值
find_md5=find $(wildcard $(1)) -type f $(patsubst -x,-and -not -path,$(DEP_FINDPARAMS) $(2)) -printf "%p%T@\n" | sort | $(MKHASH) md5
# -print0 是 find 的一个选项，用于输出以空字符（null character）分隔的文件名，null character 是个特殊字符（\0），不是空格
# xargs -0 $(MKHASH) md5：xargs 接收到find的输出后，将输出按照 null character 切割，然后传给 MKHASH 计算 md5，得到的是多个md5值

# 函数名中的 reproducible 应该是针对文件列表的，计算hash的时候没有算时间戳，所以，只要文件没有增删，应该就是一样的
# 整体功能，从 $1 中匹配出 $2 文件，依次计算文件名的md5，然后排序，再计算一次md5
find_md5_reproducible=find $(wildcard $(1)) -type f $(patsubst -x,-and -not -path,$(DEP_FINDPARAMS) $(2)) -print0 | xargs -0 $(MKHASH) md5 | sort | $(MKHASH) md5

# 总体：rdep会根据目标的依赖md5和时间戳，判断是否需要重新构建，将结果反映到 check文件的时间戳上，供make使用
# 功能上是为目标添加了基于 hash 和 时间戳 的缓存机制，避免重复构建

# reverse dependency（反向依赖）
# $(1): 通常是输入文件或目录的路径，表示当前的基准目录
# $(2): 目标名称，可以认为是构建生成的产物文件/文件夹
# $(3): 可选的，用于存储MD5值
# $(4): 可选，find 的追加参数，用于过滤出影响构建的文件
define rdep
  # 在发生错误或者信号时，也不要把 $(2) 删除，保护中间文件不被自动删除，确保构建过程的稳定性
  # 多次声明是追加关系，不会覆盖
  .PRECIOUS: $(2)
  # 在执行 $(2)_check 时，不显示命令本身，精简输出
  # 因为这个目标是系统添加的，原则上用户不太关心
  .SILENT: $(2)_check

  # 声明依赖关系，$(2) 依赖 $(2)_check
  $(2): $(2)_check
  check-depends: $(2)_check

# 检查目标文件/目录 是否存在
ifneq ($(wildcard $(2)),)
  $(2)_check::
	# $3 应该是一个标识文件，用来对比两次build源码是否变化的
	$(if $(3), \
		# 计算现在的hash，存到 $(3).1 临时文件中
		$(call find_md5,$(1),$(4)) > $(3).1; \
		# 如果之前的标识不存在 或 他俩一样，会执行后面的
		# diff 是linux命令，如果内容一样返回0，不一样返回差异内容
		{ [ \! -f "$(3)" ] || diff $(3) $(3).1 >/dev/null; } && \
	) \
	{ \
		[ -f "$(2)_check.1" ] && mv "$(2)_check.1" "$(2)_check"; \
		# 检查所有依赖文件的时间戳，如果有一个比目标文件新，就需要重新构建
	    $(TOPDIR)/scripts/timestamp.pl $(DEP_FINDPARAMS) $(4) -n $(2) $(1) && { \
			$(call debug_eval,$(SUBDIR),r,echo "No need to rebuild $(2)";) \
			# -r 用于修改文件时间戳，如果文件不存在就创建一个空文件；touch -r reference_file new_file
			# 将 $(2) 的时间戳复制到 $(2)_check
			touch -r "$(2)" "$(2)_check"; \
		} \
	} || { \
		$(call debug_eval,$(SUBDIR),r,echo "Need to rebuild $(2)";) \
		# 更新 $(2)_check 的访问时间和修改时间
		# 因为 $(2) 依赖 当前的$(2)_check，这里新建一个最新的文件，肯定会导致 $(2) 重新构建
		touch "$(2)_check"; \
	}
	# 检查完以后，检查结果已经反应到 $(2)_check 的时间戳上，为了保持同步，需要更新新的版本标识
	$(if $(3), mv $(3).1 $(3))
else
  $(2)_check::
	$(if $(3), rm -f $(3) $(3).1)
	$(call debug_eval,$(SUBDIR),r,echo "Target $(2) not built")
endif

endef

# MAKECMDGOALS 是当前用户在命令行指定的目标名，用户指定多个目标时，用空格分隔
# % 表示任意个匹配，即任意个 . 开头的字符串，简单的点
# $(if condition,then-part,else-part)：这是 Makefile 中的条件函数。如果 condition 非空，它返回 then-part，否则返回 else-part
ifeq (
	# 判断用户指定的目标是否以 . 开头
	$(filter .%,$(MAKECMDGOALS)),
	# 如果用户指定了目标，则返回目标，否则返回 x
	$(if $(MAKECMDGOALS),$(MAKECMDGOALS),x)
)
  define rdep
    $(2): $(2)_check
  endef
endif
