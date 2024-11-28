# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2007-2020 OpenWrt.org

ifeq ($(MAKECMDGOALS),prereq)
  SUBTARGETS:=prereq
  PREREQ_ONLY:=1
# For target/linux related target add dtb to selectively compile dtbs
else ifneq ($(filter target/linux/%,$(MAKECMDGOALS)),)
  SUBTARGETS:=$(DEFAULT_SUBDIR_TARGETS) dtb
else
  SUBTARGETS:=$(DEFAULT_SUBDIR_TARGETS)
endif

# 是移除 ., 只有在 返回里面有空格隔开的 . 时才算，eg：a1 b2 . c3 => a1 b2 c3
subtarget-default = $(filter-out ., \
	# 这是个优先级判断 $($(1)/builddirs-$(2)) || $($(1)/builddirs-default) || $($(1)/builddirs)
	$(if
		$($(1)/builddirs-$(2)),
		$($(1)/builddirs-$(2)), \
		$(if
			$($(1)/builddirs-default),
			$($(1)/builddirs-default), \
			$($(1)/builddirs)
		)
	)
)

# $1 subdir
# $2 target
define subtarget
	$(call warn_eval,$(1),t,T,
		# 这个会 新建目标 $(subdir)/$(target)，并配置依赖关系，将其所有的 builddirs 都作为依赖
		$(1)/$(2): $($(1)/) $(foreach
			bd,
			$(call subtarget-default,
				$(1),
				$(2)
			),
			$(1)/$(bd)/$(2)
		)
	)

endef

define ERROR
	($(call MESSAGE, $(2)); $(if $(BUILD_LOG), echo "$(2)" >> $(BUILD_LOG_DIR)/$(1)/error.txt;) $(if $(3),, exit 1;))
endef

# 获取最后一个路径
lastdir=$(word
	# 获取一共几个路径
	$(words
		# 文件分割符替换为空格   a/b/c ->  a b c
		$(subst /, ,$(1))
	),
	# 文件分割符替换为空格   a/b/c ->  a b c
	$(subst /, ,$(1))
)

# 别名？如果输入只有一级目录，返回空：输入 dir => 空
# 否则，返回最后一级目录：输入 a/b/c => c
# 这个是为了处理make目标别名的，配置 target/toolchain/download 的目标，会执行 `make -C target/toolchain download`
# 将最后一个路径作为目标名，剩下的作为makefile路径，算是一个目录的约定
diralias=$(if
	# 判断是否是子串，这里的意思可能是输入只有一级目录？
	$(findstring
		$(1),
		# 获取最后一级目录
		$(call lastdir,$(1))
	),
	,
	$(call lastdir,$(1))
)

subdir_make_opts = \
	$(if $(SUBDIR_MAKE_DEBUG),-d) -r -C $(1) \
		BUILD_SUBDIR="$(1)" \
		BUILD_VARIANT="$(4)" \
		ALL_VARIANTS="$(5)"

# 执行 make $(3)-)$(2)，根据情况，选择输出日志
# 1: subdir
# 2: target
# 3: build type
# 4: build variant
# 5: all variants
log_make = \
	# 根据debug级别，选择是否添加 @ 来禁用命令输出
	 $(if $(call debug,$(1),v),,@)+ \
	 $(if $(BUILD_LOG), \
		set -o pipefail; \
		mkdir -p $(BUILD_LOG_DIR)/$(1)$(if $(4),/$(4));) \
	$(SCRIPT_DIR)/time.pl "time: $(1)$(if $(4),/$(4))/$(if $(3),$(3)-)$(2)" \
	$$(SUBMAKE) $(subdir_make_opts) $(if $(3),$(3)-)$(2) \
		# tee 将标准输出重定向到文件，2>&1 将标准错误重定向到标准输出
		$(if $(BUILD_LOG),SILENT= 2>&1 | tee $(BUILD_LOG_DIR)/$(1)$(if $(4),/$(4))/$(if $(3),$(3)-)$(2).txt)

ifdef CONFIG_AUTOREMOVE
rebuild_check = \
	# 这一行可以简化为 make check-depends
	@-$$(NO_TRACE_MAKE) $(subdir_make_opts) check-depends >/dev/null 2>/dev/null; \
		$(if $(BUILD_LOG),mkdir -p $(BUILD_LOG_DIR)/$(1)$(if $(4),/$(4));) \
		# make $(3)-$(2)，[buildType-]Target
		$$(NO_TRACE_MAKE) $(if $(BUILD_LOG),-d) -q $(subdir_make_opts) .$(if $(3),$(3)-)$(2) \
			> $(if $(BUILD_LOG),$(BUILD_LOG_DIR)/$(1)$(if $(4),/$(4))/check-$(if $(3),$(3)-)$(2).txt,/dev/null) 2>&1 || \
			# make clean-build
			$$(SUBMAKE) $(subdir_make_opts) clean-build >/dev/null 2>/dev/null

endif

# Parameters: <subdir>
define subdir
  $(call warn,$(1),d,D $(1))
  # 由外部指定，builddirs 是子目录
  $(foreach bd,$($(1)/builddirs),
    $(call warn,$(1),d,BD $(1)/$(bd))
    $(foreach target,$(SUBTARGETS) $($(1)/subtargets),
      $(foreach btype,$(buildtypes-$(bd)),
	  	# warn_eval 会执行第四个参数，T 后面那个
        $(call warn_eval,$(1)/$(bd),t,T,
			# 定义了一个目标依赖关系
			$(1)/$(bd)/$(btype)/$(target): $(if
				$(NO_DEPS)$(QUILT),
				,
				$($(1)/$(bd)/$(btype)/$(target)) $(call
					$(1)//$(btype)/$(target),
					$(1)/$(bd)/$(btype)
				)
			)
		)
		# 执行 make $(btype)-$(target)
		$(call log_make,$(1)/$(bd),$(target),$(btype),$(filter-out __default,$(variant)),$($(1)/$(bd)/variants)) \
			# 异常处理
			|| $(call ERROR,$(2),   ERROR: $(1)/$(bd) [$(btype)] failed to build.,$(findstring $(bd),$($(1)/builddirs-ignore-$(btype)-$(target))))
		# 这是个依赖处理，以路径的最后一级作为 bd（buildDir） 的别名
        $(if
			$(call diralias,$(bd)),
			$(call warn_eval,$(1)/$(bd),l,T,
				$(1)/$(call diralias,$(bd))/$(btype)/$(target): $(1)/$(bd)/$(btype)/$(target)))
      	)
      	$(call warn_eval,$(1)/$(bd),t,T,
	  		$(1)/$(bd)/$(target): $(if
				$(NO_DEPS)$(QUILT),
				,
				$($(1)/$(bd)/$(target)
			) $(call $(1)//$(target),$(1)/$(bd))))
        $(foreach
			variant,
			$(filter-out
				# filter-out 不是正则，这里的 * 就是字符串 *，不是通配符
				*,
				# 下面是一个优先级处理：BUILD_VARIANT || $($(1)/$(bd)/variants) || $($(1)/$(bd)/default-variant) || __default
				$(if
					$(BUILD_VARIANT),
					$(BUILD_VARIANT),
					# 优先返回 $($(1)/$(bd)/variants)，否则计算
					$(if
						$(strip
							$($(1)/$(bd)/variants)
						),
						$($(1)/$(bd)/variants),
						# 优先 $($(1)/$(bd)/default-variant)，否则返回 __default
						$(if
							$($(1)/$(bd)/default-variant),
							$($(1)/$(bd)/default-variant),
							__default
						)
					)
				)
			),
			# 这里开始是 foreach 的执行块
			$(if $(BUILD_LOG),@mkdir -p $(BUILD_LOG_DIR)/$(1)/$(bd)/$(filter-out __default,$(variant)))
			$(if
				$($(1)/autoremove),
				$(call rebuild_check,
					$(1)/$(bd),
					$(target),
					,
					$(filter-out __default,$(variant)),
					$($(1)/$(bd)/variants)
				)
			)
			# 执行 make $(3)-$(2)
			$(call log_make,
				$(1)/$(bd),
				$(target),
				,
				$(filter-out __default,$(variant)),
				$($(1)/$(bd)/variants)
			) \
				|| $(call ERROR,$(1),   ERROR: $(1)/$(bd) failed to build$(if $(filter-out __default,$(variant)), (build variant: $(variant))).,$(findstring $(bd),$($(1)/builddirs-ignore-$(target))))
        )
      	$(if $(PREREQ_ONLY)$(DUMP_TARGET_DB),,
        	# aliases
        	$(if
				$(call diralias,$(bd)),
				$(call warn_eval,$(1)/$(bd),l,T,
					$(1)/$(call diralias,$(bd))/$(target): $(1)/$(bd)/$(target)
				)
			)
	  )
	)
  )
  $(foreach target,$(SUBTARGETS) $($(1)/subtargets),$(call subtarget,$(1),$(target)))
endef

ifndef DUMP_TARGET_DB
# 这貌似是个缓存函数，当执行对应脚本时，会生成时间戳，如果时间戳都比依赖新，就不会重复执行
# Parameters: <subdir> <name> <target> <depends> <config options> <stampfile location>
# Parameters: <1>      <2>    <3>      <4>       <5>              <6>
# Parameters: 子目录    目标名  <target> <depends> <config options> <stampfile location>
define stampfile
  # 这是一个文件路径
  # 这是个变量，后面会用于定义目标依赖，比如：$(target/stamp-compile) 、$(package/stamp-compile) 这种就是引用了这个变量
  $(1)/stamp-$(3):=$(if $(6),$(6),$(STAGING_DIR))/stamp/.$(2)_$(3)$(5)
  # 定义目标依赖关系，有两个 $$ ，说明是取了上面定义变量的值
  $$($(1)/stamp-$(3)): $(TMP_DIR)/.build $(4)
    # 如果 subdir 里面最后修改的时间比 stamp-$(3) 的时间戳新【根据返回码确定】，就执行make
	# 否则，不需要重新make
	@+$(SCRIPT_DIR)/timestamp.pl -n $$($(1)/stamp-$(3)) $(1) $(4) || \
		# 这里最终执行的 $(1)/$(3) 是 subdir/target，会在 subdir 中被定义
		# subdir/target 会依赖所有子目录的 target，导致所有子目录的 target 都会被执行
		$(MAKE) $(if $(QUIET),--no-print-directory) $$($(1)/flags-$(3)) $(1)/$(3)
	# 先获取目标所在的文件夹，然后创建，确保后面的touch不报错
	@mkdir -p $$$$(dirname $$($(1)/stamp-$(3)))
	@touch $$($(1)/stamp-$(3))

  # $(call debug,$(1),v)
  # $$(if debug,,.SILENT: $$($(1)/stamp-$(3)))
  $$(if $(call debug,$(1),v),,.SILENT: $$($(1)/stamp-$(3)))

  # 保护时间戳文件不被删除
  .PRECIOUS: $$($(1)/stamp-$(3)) # work around a make bug

  $(1)//clean:=$(1)/stamp-$(3)/clean
  $(1)/stamp-$(3)/clean: FORCE
	@rm -f $$($(1)/stamp-$(3))

endef
endif
