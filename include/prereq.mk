# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2006-2020 OpenWrt.org

# 这个文件是 prereq 的定义和 utils 函数

# 避免重复include
ifneq ($(__prereq_inc),1)
__prereq_inc:=1

prereq:
	if [ -f $(TMP_DIR)/.prereq-error ]; then \
		echo; \
		cat $(TMP_DIR)/.prereq-error; \
		rm -f $(TMP_DIR)/.prereq-error; \
		echo; \
		false; \
	fi

.SILENT: prereq
endif

PREREQ_PREV=

# 1: display name
# 2: error message
define Require
  export PREREQ_CHECK=1
  # 重复校验
  ifeq ($$(CHECK_$(1)),)
    prereq: prereq-$(1)

	# 这个依赖是保证顺序的，PREREQ_PREV 是上一个调用 Require 的参数
	# 为了按照调用顺序进行检查，这里声明依赖
    prereq-$(1): $(if $(PREREQ_PREV),prereq-$(PREREQ_PREV)) FORCE
		printf "Checking '$(1)'... "
		# MAKEFILE_LIST 是内置变量，包含了所有解析的 makefile 文件
		# firstword 是获取第一个元素
		# 使用原始的makefile执行 check-$(1) 目标，正常返回就认为测试通过
		if $(NO_TRACE_MAKE) -f $(firstword $(MAKEFILE_LIST)) check-$(1) PATH="$(ORIG_PATH)" >/dev/null 2>/dev/null; then \
			echo 'ok.'; \
		elif $(NO_TRACE_MAKE) -f $(firstword $(MAKEFILE_LIST)) check-$(1) PATH="$(ORIG_PATH)" >/dev/null 2>/dev/null; then \
			echo 'updated.'; \
		else \
			echo 'failed.'; \
			echo "$(PKG_NAME): $(strip $(2))" >> $(TMP_DIR)/.prereq-error; \
		fi

    check-$(1): FORCE
	  $(call Require/$(1))
    CHECK_$(1):=1

    .SILENT: prereq-$(1) check-$(1)
    .NOTPARALLEL:
  endif

  PREREQ_PREV=$(1)
endef


define RequireCommand
  define Require/$(1)
    command -v $(1)
  endef

  $$(eval $$(call Require,$(1),$(2)))
endef

define RequireHeader
  define Require/$(1)
    [ -e "$(1)" ]
  endef

  $$(eval $$(call Require,$(1),$(2)))
endef

# 尝试引入指定的头文件，并进行编译，不报错就通过
# 1: header to test
# 2: failure message
# 3: optional compile time test
# 4: optional link library test (example -lncurses)
define RequireCHeader
  define Require/$(1)
    echo 'int main(int argc, char **argv) { $(3); return 0; }' | gcc -include $(1) -x c -o $(TMP_DIR)/a.out - $(4)
  endef

  $$(eval $$(call Require,$(1),$(2)))
endef

# 转义引号
define QuoteHostCommand
'$(subst ','"'"',$(strip $(1)))'
endef

# 只是测试 $3 是否满足条件
# 1: display name
# 2: failure message
# 3: test
define TestHostCommand
  # 先定义测试命令
  define Require/$(1)
	($(3)) >/dev/null 2>/dev/null
  endef

  # 注册公共依赖部分
  $$(eval $$(call Require,$(1),$(2)))
endef

# 本身只是定义了很多宏和依赖
# 测试 $1 是否满足条件，是的话将其软链到 $(STAGING_DIR_HOST)/bin/$1 下
# 1: canonical name，二进制的名字
# 2: failure message，失败的提示信息
# 3+: candidates，测试命令，只有测试命令成功，才会执行软链接
define SetupHostCommand
  define Require/$(1)
	mkdir -p "$(STAGING_DIR_HOST)/bin"; \
	for cmd in $(call QuoteHostCommand,$(3)) $(call QuoteHostCommand,$(4)) \
	           $(call QuoteHostCommand,$(5)) $(call QuoteHostCommand,$(6)) \
	           $(call QuoteHostCommand,$(7)) $(call QuoteHostCommand,$(8)) \
	           $(call QuoteHostCommand,$(9)) $(call QuoteHostCommand,$(10)) \
	           $(call QuoteHostCommand,$(11)) $(call QuoteHostCommand,$(12)); do \
		if [ -n "$$$$$$$$cmd" ]; then \
			# ${cmd%% *} 是参数扩展，用于从 cmd 中删除第一个空格及其后的所有内容，基本上是获取命令名
			# command -v 是linux命令，用于获取命令的二进制路径
			bin="$$$$$$$$(command -v "$$$$$$$${cmd%% *}")"; \
			# 如果命令可执行，并且执行成功
			if [ -x "$$$$$$$$bin" ] && eval "$$$$$$$$cmd" >/dev/null 2>/dev/null; then \
				# ls -dl 列出目标文件的详细信息，包括符号链接的目标
				case "$$$$$$$$(ls -dl -- $(STAGING_DIR_HOST)/bin/$(strip $(1)))" in \
					# 下面是 case in 的条件，匹配任意一个都会执行下面的操作
					# 表示普通文件
					"-"* | \
					# 表示已经是一个指向 $bin 的符号链接了
					*" -> $$$$$$$$bin"* | \
					# 匹配符号链接指向非根目录的情况
					*" -> "[!/]*) \
						# 上面几种匹配是检查当前的符号链接是否已经是正确的了，什么都不做
						# 以免更新了时间戳，导致make的缓存失效
						[ -x "$(STAGING_DIR_HOST)/bin/$(strip $(1))" ] && exit 0 \
						;; \
				esac; \
				# 将其链接到 STAGING_DIR_HOST/bin 目录下
				ln -sf "$$$$$$$$bin" "$(STAGING_DIR_HOST)/bin/$(strip $(1))"; \
				exit 1; \
			fi; \
		fi; \
	done; \
	exit 1
  endef

  # $2 是异常信息，这里进行了默认值兜底
  $$(eval $$(call Require,$(1),$(if $(2),$(2),Missing $(1) command)))
endef
