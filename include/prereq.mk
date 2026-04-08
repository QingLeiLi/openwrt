# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2006-2020 OpenWrt.org

# 这个文件是 prereq 的定义和 utils 函数
# OpenWrt/Make 的“先决条件检查（prereq）”框架。它提供一套通用宏
# （Require/RequireCommand/RequireHeader/RequireCHeader/TestHostCommand/SetupHostCommand）
# 来检查宿主机或构建环境是否具备某命令/头文件/库，并在需要时“自修正”（比如创建工具别名），最终将失败信息集中显示。

# 避免重复include
ifneq ($(__prereq_inc),1)
__prereq_inc:=1

# 主入口
prereq:
	# 若存在 $(TMP_DIR)/.prereq-error，则打印其中累计的失败条目并返回失败，统一出口
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
	# 为了按照调用顺序进行检查，这里声明依赖，当前的 prereq 依赖 上一个 prereq
    prereq-$(1): $(if $(PREREQ_PREV),prereq-$(PREREQ_PREV)) FORCE
		printf "Checking '$(1)'... "
		# MAKEFILE_LIST 是内置变量，包含了所有解析的 makefile 文件
		# firstword 是获取第一个元素
		# 使用原始的makefile执行 check-$(1) 目标，正常返回就认为测试通过
		if $(NO_TRACE_MAKE) -f $(firstword $(MAKEFILE_LIST)) check-$(1) PATH="$(ORIG_PATH)" >/dev/null 2>/dev/null; then \
			echo 'ok.'; \
		# 双次执行策略，允许检查动作在第一次“修正环境”（如创建链接、下载工具等），让第二次复查通过，并显示 updated.
		elif $(NO_TRACE_MAKE) -f $(firstword $(MAKEFILE_LIST)) check-$(1) PATH="$(ORIG_PATH)" >/dev/null 2>/dev/null; then \
			echo 'updated.'; \
		else \
			echo 'failed.'; \
			# 失败时把消息累积到 $(TMP_DIR)/.prereq-error，统一在主 prereq 目标里输出，便于一次性查看所有缺失项
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


# 最简单的“命令存在性”检查
define RequireCommand
  define Require/$(1)
    command -v $(1)
  endef

  $$(eval $$(call Require,$(1),$(2)))
endef

# 用于检查路径的存在性（例如 /usr/include/xxx.h）
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
    echo 'int main(int argc, char **argv) { $(3); return 0; }' | $(STAGING_DIR_HOST)/bin/gcc -include $(1) -x c -o $(TMP_DIR)/a.out - $(4)
  endef

  $$(eval $$(call Require,$(1),$(2)))
endef

# 转义引号
define QuoteHostCommand
'$(subst ','"'"',$(strip $(1)))'
endef

# 只是测试 $3 是否满足条件
# 自由传入任意测试表达式 $(3)（如 “python3 -c 'import ssl'”）
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

# 为“规范命令名”在 $(STAGING_DIR_HOST)/bin 创建一个稳定入口（符号链接），指向宿主可用的若干候选命令之一，并验证命令能跑通
# 本身只是定义了很多宏和依赖
# 测试 $1 是二进制的名字（eg：python），$3 往后都是测试指令(eg： python3 -v；python2 -v)，哪个测试成功了，就把谁链接为 $1
# 软链到 $(STAGING_DIR_HOST)/bin/$1 下，提供给后续编译使用
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
				# ln -sf "$$$$$$$$bin" "$(STAGING_DIR_HOST)/bin/$(strip $(1))"; \
				ln -sf "$$$$$$$${bin#$(STAGING_DIR_HOST)/bin/}" "$(STAGING_DIR_HOST)/bin/$(strip $(1))"; \
				# 异常退出，但是测试有二次重试，会再检查一次
				exit 1; \
			fi; \
		fi; \
	done; \
	exit 1
  endef

  # $2 是异常信息，这里进行了默认值兜底
  $$(eval $$(call Require,$(1),$(if $(2),$(2),Missing $(1) command)))
endef
