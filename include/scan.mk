include $(TOPDIR)/include/verbose.mk
include $(TOPDIR)/rules.mk
# make 命令行中的变量优先级是比 Makefile 中的高，外部可以覆盖这个变量
TMP_DIR:=$(TOPDIR)/tmp

# 并不是内置的特殊目标，而是放在一开始，作为默认目标
all: $(TMP_DIR)/.$(SCAN_TARGET)

SCAN_TARGET ?= packageinfo
SCAN_NAME ?= package
SCAN_DIR ?= package
TARGET_STAMP:=$(TMP_DIR)/info/.files-$(SCAN_TARGET).stamp
# SCAN_COOKIE 是 ./scripts/feeds 设置的pid
FILELIST:=$(TMP_DIR)/info/.files-$(SCAN_TARGET)-$(SCAN_COOKIE)
OVERRIDELIST:=$(TMP_DIR)/info/.overrides-$(SCAN_TARGET)-$(SCAN_COOKIE)

export ORIG_PATH:=$(if $(ORIG_PATH),$(ORIG_PATH),$(PATH))
# 追加 STAGING_DIR_HOST 的 bin
export PATH:=$(STAGING_DIR_HOST)/bin:$(PATH)

# 如果 $1 以 feeds/ 开头，那么返回 feeds/${this}，否则返回空
define feedname
$(if
	# 将 $1 中的 feeds/ 前缀去掉
	$(patsubst feeds/%,,$(1)),
	,
	# subst 将 / 替换为 空格
	# word 取第二个
	$(word 2,$(subst /, ,$(1)))
)
endef

# 根据 target 和 packge 添加不同的makefile文件
ifeq ($(SCAN_NAME),target)
  SCAN_DEPS=image/Makefile profiles/*.mk $(TOPDIR)/include/kernel*.mk $(TOPDIR)/include/target.mk image/*.mk
else
  SCAN_DEPS=$(TOPDIR)/include/package*.mk
# 添加特定 feed 的makefile
ifneq ($(call feedname,$(SCAN_DIR)),)
  SCAN_DEPS += $(TOPDIR)/feeds/$(call feedname,$(SCAN_DIR))/*.mk
endif
endif

ifeq ($(IS_TTY),1)
  ifneq ($(strip $(NO_COLOR)),1)
    define progress
	printf "\033[M\r$(1)" >&2;
    endef
  else
    define progress
	printf "\r$(1)" >&2;
    endef
  endif
else
  define progress
	:;
  endef
endif

# $(eval $(call
# PackageDir,
# 	applications_luci-app-acl,
# 	applications/luci-app-acl,
# ))
# $1：info
# $2：dir
# $3：pkg
define PackageDir
  $(TMP_DIR)/.$(SCAN_TARGET): $(TMP_DIR)/info/.$(SCAN_TARGET)-$(1)
  $(TMP_DIR)/info/.$(SCAN_TARGET)-$(1): $(SCAN_DIR)/$(2)/Makefile $(foreach DEP,$(DEPS_$(SCAN_DIR)/$(2)/Makefile) $(SCAN_DEPS),$(wildcard $(if $(filter /%,$(DEP)),$(DEP),$(SCAN_DIR)/$(2)/$(DEP))))
	# 后面复杂的部分：
	# $(DEPS_$(SCAN_DIR)/$(2)/Makefile) 是一个变量，目标（$(TMP_DIR)/info/.files-$(SCAN_TARGET).mk） 里面通过 awk 生成的
	# $(SCAN_DEPS) 是拼接的额外依赖
	# $(foreach DEP,$(DEPS_$(SCAN_DIR)/$(2)/Makefile) $(SCAN_DEPS),
	# 	$(wildcard
	#       这个是处理路径的，绝对路径直接返回，相对路径拼接 SCAN_DIR 和包名
	# 		$(if
	# 			$(filter /%,$(DEP)),
	# 			$(DEP),
	# 			$(SCAN_DIR)/$(2)/$(DEP)
	# 		)
	# 	)
	# )
	{ \
		# 只是打印日志
		$$(call progress,Collecting $(SCAN_NAME) info: $(SCAN_DIR)/$(2)) \
		# 输出内容：Source-Makefile: feeds/luci/libs/luci-lib-ip/Makefile
		echo Source-Makefile: $(SCAN_DIR)/$(2)/Makefile; \
		$(if $(3),echo Override: $(3),true); \
		# -C 是在指定目录下执行make
		# 这个if是根据日志级别，选择是 MAKE 还是 NO_TRACE_MAKE
		# 这里会执行包的 Makefile
		$(if $(findstring c,$(OPENWRT_VERBOSE)),$(MAKE),$(NO_TRACE_MAKE) --no-print-dir) -r DUMP=1 FEED="$(call feedname,$(2))" -C $(SCAN_DIR)/$(2) $(SCAN_MAKEOPTS) \
			# 根据日志级别确定，是否要重定向异常
			$(if $(findstring c,$(OPENWRT_VERBOSE)),,2>/dev/null) || { \
			# 失败了，创建日志目录
			mkdir -p "$(TOPDIR)/logs/$(SCAN_DIR)/$(2)"; \
			# 重新执行一遍，把日志写过去
			$(NO_TRACE_MAKE) --no-print-dir -r DUMP=1 FEED="$(call feedname,$(2))" -C $(SCAN_DIR)/$(2) $(SCAN_MAKEOPTS) > $(TOPDIR)/logs/$(SCAN_DIR)/$(2)/dump.txt 2>&1; \
			$$(call progress,ERROR: please fix $(SCAN_DIR)/$(2)/Makefile - see logs/$(SCAN_DIR)/$(2)/dump.txt for details\n) \
			rm -f $$@; \
		}; \
		echo; \
	} > $$@.tmp
	mv $$@.tmp $$@
endef

# 执行顺序 1
$(OVERRIDELIST):
	# 删除缓存
	rm -f $(TMP_DIR)/info/.overrides-$(SCAN_TARGET)-*
	# 更新时间戳，这里 $@ 代表目标名（$(OVERRIDELIST)），即 $(TMP_DIR)/info/.overrides-$(SCAN_TARGET)-$(SCAN_COOKIE)
	touch $@

ifeq ($(SCAN_NAME),target)
  GREP_STRING=BuildTarget
else
  GREP_STRING=(Build/DefaultTargets|BuildPackage|KernelPackage)
endif

# 执行顺序 2
# FILELIST 存储的是 feed 下所有的包名路径，类似于：
	# libs/bcg729
	# libs/libosip2
	# libs/libctb
	# libs/iksemel
	# libs/pjproject
	# libs/sofia-sip
	# libs/dahdi-linux
	# libs/re
$(FILELIST): $(OVERRIDELIST)
	rm -f $(TMP_DIR)/info/.files-$(SCAN_TARGET)-*
	# -L 跟随符号链接
	# 查找目录下所有的 Makefile，每个都对应一个包
		# find -L feeds/telephony -mindepth 1 -maxdepth 5 -name Makefile
			# feeds/telephony/net/asterisk-opus/Makefile
			# feeds/telephony/net/asterisk-chan-lantiq/Makefile
		# find -L package -mindepth 1 -name Makefile
			# package/feeds/telephony/asterisk-g72x/Makefile
			# package/feeds/telephony/asterisk-chan-sccp/Makefile
	# 将输出的路径使用 GREP_STRING 进行过滤，得到每个包的 构建命令，会有一些额外数据输出，注释啥的
		# find -L feeds/telephony -mindepth 1 -maxdepth 5 -name Makefile | xargs grep -aHE 'call Build/DefaultTargets|BuildPackage|KernelPackage'
			# feeds/telephony/net/sipgrep/Makefile:$(eval $(call BuildPackage,sipgrep))
			# feeds/telephony/net/sngrep/Makefile:$(eval $(call BuildPackage,sngrep))
			# feeds/telephony/net/rtpengine/Makefile:define KernelPackage/ipt-rtpengine
			# feeds/telephony/net/rtpengine/Makefile:define KernelPackage/ipt-rtpengine/conffiles
			# feeds/telephony/net/rtpengine/Makefile:define KernelPackage/ipt-rtpengine/description
			# feeds/telephony/net/rtpengine/Makefile:# KernelPackage calls need to go first, otherwise hooks like
			# feeds/telephony/net/rtpengine/Makefile:$(eval $(call KernelPackage,ipt-rtpengine))
		# find -L package -mindepth 1 -name Makefile | xargs grep -aHE 'call (Build/DefaultTargets|BuildPackage|KernelPackage)'
			# package/feeds/telephony/sipp/Makefile:$(eval $(call BuildPackage,sipp))
			# package/feeds/telephony/asterisk-g72x/Makefile:$(eval $(call BuildPackage,asterisk-codec-g729))
			# package/feeds/telephony/asterisk-chan-sccp/Makefile:$(eval $(call BuildPackage,asterisk-chan-sccp))

	# 删除前面的路径和后面的 Makefile 文件名
		# find -L feeds/telephony -mindepth 1 -maxdepth 5 -name Makefile | xargs grep -aHE 'call Build/DefaultTargets|BuildPackage|KernelPackage' | sed -e 's#^feeds/telephony/##' -e 's#/Makefile:.*##'
			# net/asterisk-opus
			# net/asterisk-opus
			# net/asterisk-chan-lantiq
			# net/asterisk-chan-dongle
		# 这个在 prepare-tmpinfo: 里面扫描 package 会有这种情况
		# find -L package -mindepth 1 -name Makefile | xargs grep -aHE 'call (Build/DefaultTargets|BuildPackage|KernelPackage)' | sed -e 's#^package/##' -e 's#/Makefile:.*##'
			# feeds/telephony/dahdi-tools
			# feeds/telephony/dahdi-tools
			# feeds/telephony/dahdi-tools
			# feeds/telephony/sipp
			# feeds/telephony/asterisk-g72x
			# feeds/telephony/asterisk-chan-sccp
	# 去重
	# 使用 include/scan.awk 处理文件名，文件主要处理了重名的问题，重名的部分包名写入了 OVERRIDELIST 中
	# 将内容写入到 $(TMP_DIR)/info/.files-$(SCAN_TARGET)-$(SCAN_COOKIE) 文件，-v 是定义变量，-f 是交给独立文件处理
	# FILELIST最终的样子是：
		# feeds/telephony/sofia-sip
		# feeds/telephony/spandsp
		# feeds/telephony/spandsp3
		# feeds/telephony/yate
	find -L $(SCAN_DIR) -mindepth 1 $(if $(SCAN_DEPTH),-maxdepth $(SCAN_DEPTH)) $(SCAN_EXTRA) -name Makefile | xargs grep -aHE 'call $(GREP_STRING)' | sed -e 's#^$(SCAN_DIR)/##' -e 's#/Makefile:.*##' | uniq | awk -v of=$(OVERRIDELIST) -f include/scan.awk > $@

# 执行顺序 3
# 这是一个所有包的汇总文件
# cat ./tmp/info/.files-packageinfo.mk
$(TMP_DIR)/info/.files-$(SCAN_TARGET).mk: $(FILELIST)
	( \
		# $< 代表第一个依赖，即 $(FILELIST)
		# 将每行拼接回完整的 makefile 路径
			# cat ./feeds/telephony.tmp/info/.files-packageinfo-3356 | awk '{print "feeds/telephony/" $0 "/Makefile" }'
				# feeds/telephony/net/asterisk-opus/Makefile
				# feeds/telephony/net/asterisk-chan-lantiq/Makefile
				# feeds/telephony/net/asterisk-chan-dongle/Makefile
				# feeds/telephony/net/rtpproxy/Makefile
		#
		# 读取 FILELIST
		# cat ./tmp/info/.files-packageinfo-4731
			# feeds/telephony/spandsp3
			# feeds/telephony/yate
		cat $< |
		# 将包名还原会完整的 makefile 路径
		# feeds/telephony/yate => package/feeds/telephony/yate/Makefile
		# cat ./tmp/info/.files-packageinfo-4731 | awk '{print "package/" $$0 "/Makefile" }'
			# package/feeds/telephony/spandsp3/Makefile
			# package/feeds/telephony/yate/Makefile
		awk '{print "$(SCAN_DIR)/" $$0 "/Makefile" }' |
		# 在每个 makefile 中搜索包含 SCAN_DEPS= 的行
		# -H 需要包含文件名，-E 使用拓展正则表达式
		# ^ 表示行的开始、* 表示零个或多个空格、*= * 表示 SCAN_DEPS 后面可能有零个或多个空格
		# cat ./tmp/info/.files-packageinfo-4731 | awk '{print "package/" $$0 "/Makefile" }' | xargs grep -HE '^ *SCAN_DEPS *= *'
			# package/firmware/linux-firmware/Makefile:SCAN_DEPS = *.mk
			# package/kernel/linux/Makefile:SCAN_DEPS=modules/*.mk $(SUBTARGET_MODULES) $(TOPDIR)/include/netfilter.mk
		xargs grep -HE '^ *SCAN_DEPS *= *' |
		# -F 设置分割符为 :，用于拆分 文件名 和 匹配的行
		# gsub 是个函数，用于替换匹配到的部分，$2 指的是针对第二部分进行替换
		# $1 和 $2 是awk分割的两部分，$1 是文件名，$2 是匹配到的行
		# gsub则是将 $2 中的 SCAN_DEPS= 替换为空，只保留了等号后面的依赖
			# cat ./tmp/info/.files-packageinfo-4731 | awk '{print "package/" $$0 "/Makefile" }' | xargs grep -HE '^ *SCAN_DEPS *= *' | awk -F: '{ gsub(/^.*DEPS *= */, "", $2); print "DEPS_" $1 "=" $2 }';
				# 这是定义了两个变量，会被 PackageDir 使用
				# DEPS_package/firmware/linux-firmware/Makefile=*.mk
				# DEPS_package/kernel/linux/Makefile=modules/*.mk $(SUBTARGET_MODULES) $(TOPDIR)/include/netfilter.mk
		awk -F: '{ gsub(/^.*DEPS *= */, "", $$2); print "DEPS_" $$1 "=" $$2 }'; \
		# 上面这个awk的作用是输出 DEPS_文件名=依赖，到目标文件里面了

		# 下面这个 awk 并没有直接收到上面的管道，是在最下面用 $< 传过去的
		# -F 设置字段分割符
		# -v 定义了两个变量
		awk -F/ -v deps="$$DEPS" -v of="$(OVERRIDELIST)" ' \
		BEGIN { \
			# 读取 OVERRIDELIST 文件，将内容写入 override 数组
			while (getline < (of)) \
				override[$$NF]=$$0; \
			close(of) \
		} \
		{ \
			# 这里拿到的 $0 跟 BEGIN 没关系，是从管道传过来的
			# 整行赋值给 info
			info=$$0; \
			# 将路径分割的 / 替换为 _
			gsub(/\//, "_", info); \
			# 也是整行赋值，是原始值，没有经过替换的
			dir=$$0; \
			pkg=""; \
			if($$NF in override) \
				# override 里存的是包名？
				pkg=override[$$NF]; \
			print "$$(eval $$(call PackageDir," info "," dir "," pkg "))"; \
			# $< 表示第一个依赖，从 FILELIST 读取的
		} ' < $<; \
		# 即使 awk处理失败了，也不要报错
		true; \
	) > $@.tmp
	# 最终文件长这样
		# DEPS_package/firmware/linux-firmware/Makefile=*.mk
		# DEPS_package/kernel/linux/Makefile=modules/*.mk $(SUBTARGET_MODULES) $(TOPDIR)/include/netfilter.mk
		# $(eval $(call PackageDir,applications_luci-app-acl,applications/luci-app-acl,))
		# $(eval $(call PackageDir,applications_luci-app-acme,applications/luci-app-acme,))
		# $(eval $(call PackageDir,applications_luci-app-adblock,applications/luci-app-adblock,))
		# $(eval $(call PackageDir,applications_luci-app-adblock-fast,applications/luci-app-adblock-fast,))
		# $(eval $(call PackageDir,applications_luci-app-advanced-reboot,applications/luci-app-advanced-reboot,))
	mv $@.tmp $@

# -include 表示要 include，但是如果文件不存在，也不要报错
# 因为这里是include了一个目标名，第一次执行时文件不存在，make会执行上面的 $(TMP_DIR)/info/.files-$(SCAN_TARGET).mk 目标，来生成该文件
# mk文件被生成吼，开始被 include，里面的 eval 会被执行
-include $(TMP_DIR)/info/.files-$(SCAN_TARGET).mk

$(TARGET_STAMP)::
	+( \
		$(NO_TRACE_MAKE) $(FILELIST); \
		MD5SUM=$$(cat $(FILELIST) $(OVERRIDELIST) | $(MKHASH) md5 | awk '{print $$1}'); \
		[ -f "$@.$$MD5SUM" ] || { \
			rm -f $@.*; \
			touch $@.$$MD5SUM; \
			touch $@; \
		} \
	)

$(TMP_DIR)/.$(SCAN_TARGET): $(TARGET_STAMP)
	$(call progress,Collecting $(SCAN_NAME) info: merging...)
	-cat $(FILELIST) | awk '{gsub(/\//, "_", $$0);print "$(TMP_DIR)/info/.$(SCAN_TARGET)-" $$0}' | xargs cat > $@ 2>/dev/null
	$(call progress,Collecting $(SCAN_NAME) info: done)
	echo

FORCE:
.PHONY: FORCE
.NOTPARALLEL:
