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
export PATH:=$(STAGING_DIR_HOST)/bin:$(PATH)

define feedname
$(if $(patsubst feeds/%,,$(1)),,$(word 2,$(subst /, ,$(1))))
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

define PackageDir
  $(TMP_DIR)/.$(SCAN_TARGET): $(TMP_DIR)/info/.$(SCAN_TARGET)-$(1)
  $(TMP_DIR)/info/.$(SCAN_TARGET)-$(1): $(SCAN_DIR)/$(2)/Makefile $(foreach DEP,$(DEPS_$(SCAN_DIR)/$(2)/Makefile) $(SCAN_DEPS),$(wildcard $(if $(filter /%,$(DEP)),$(DEP),$(SCAN_DIR)/$(2)/$(DEP))))
	{ \
		# 只是打印日志
		$$(call progress,Collecting $(SCAN_NAME) info: $(SCAN_DIR)/$(2)) \
		# 输出内容：Source-Makefile: feeds/luci/libs/luci-lib-ip/Makefile
		echo Source-Makefile: $(SCAN_DIR)/$(2)/Makefile; \
		$(if $(3),echo Override: $(3),true); \
		# -C 是在指定目录下执行make
		$(if $(findstring c,$(OPENWRT_VERBOSE)),$(MAKE),$(NO_TRACE_MAKE) --no-print-dir) -r DUMP=1 FEED="$(call feedname,$(2))" -C $(SCAN_DIR)/$(2) $(SCAN_MAKEOPTS) \
			$(if $(findstring c,$(OPENWRT_VERBOSE)),,2>/dev/null) || { \
			mkdir -p "$(TOPDIR)/logs/$(SCAN_DIR)/$(2)"; \
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
	# 将输出的路径使用 GREP_STRING 进行过滤，得到每个包的 构建命令，会有一些额外数据输出，注释啥的
		# find -L feeds/telephony -mindepth 1 -maxdepth 5 -name Makefile | xargs grep -aHE 'call Build/DefaultTargets|BuildPackage|KernelPackage'
			# feeds/telephony/net/sipgrep/Makefile:$(eval $(call BuildPackage,sipgrep))
			# feeds/telephony/net/sngrep/Makefile:$(eval $(call BuildPackage,sngrep))
			# feeds/telephony/net/rtpengine/Makefile:define KernelPackage/ipt-rtpengine
			# feeds/telephony/net/rtpengine/Makefile:define KernelPackage/ipt-rtpengine/conffiles
			# feeds/telephony/net/rtpengine/Makefile:define KernelPackage/ipt-rtpengine/description
			# feeds/telephony/net/rtpengine/Makefile:# KernelPackage calls need to go first, otherwise hooks like
			# feeds/telephony/net/rtpengine/Makefile:$(eval $(call KernelPackage,ipt-rtpengine))
	# 删除前面的路径和后面的 Makefile 文件名
		# find -L feeds/telephony -mindepth 1 -maxdepth 5 -name Makefile | xargs grep -aHE 'call Build/DefaultTargets|BuildPackage|KernelPackage' | sed -e 's#^feeds/telephony/##' -e 's#/Makefile:.*##'
			# net/asterisk-opus
			# net/asterisk-opus
			# net/asterisk-chan-lantiq
			# net/asterisk-chan-dongle
	# 去重
	# 使用 include/scan.awk 处理文件名，文件主要处理了重名的问题，将包名 和 feed名 重名的部分包名写入了 OVERRIDELIST 中
	# 将内容写入到 $(TMP_DIR)/info/.files-$(SCAN_TARGET)-$(SCAN_COOKIE) 文件，-v 是定义变量，-f 是交给独立文件处理
	find -L $(SCAN_DIR) -mindepth 1 $(if $(SCAN_DEPTH),-maxdepth $(SCAN_DEPTH)) $(SCAN_EXTRA) -name Makefile | xargs grep -aHE 'call $(GREP_STRING)' | sed -e 's#^$(SCAN_DIR)/##' -e 's#/Makefile:.*##' | uniq | awk -v of=$(OVERRIDELIST) -f include/scan.awk > $@

# 执行顺序 3
$(TMP_DIR)/info/.files-$(SCAN_TARGET).mk: $(FILELIST)
	( \
		# $< 代表第一个依赖，即 $(FILELIST)
		# 将每行拼接回完整的 makefile 路径
			# cat ./feeds/telephony.tmp/info/.files-packageinfo-3356 | awk '{print "feeds/telephony/" $0 "/Makefile" }'
				# feeds/telephony/net/asterisk-opus/Makefile
				# feeds/telephony/net/asterisk-chan-lantiq/Makefile
				# feeds/telephony/net/asterisk-chan-dongle/Makefile
				# feeds/telephony/net/rtpproxy/Makefile
		# 在每个 makefile 中搜索包含 SCAN_DEPS 的行
		# 这个好像一直是空的？
		cat $< | awk '{print "$(SCAN_DIR)/" $$0 "/Makefile" }' | xargs grep -HE '^ *SCAN_DEPS *= *' | awk -F: '{ gsub(/^.*DEPS *= */, "", $$2); print "DEPS_" $$1 "=" $$2 }'; \
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
			# 整行赋值给 info
			info=$$0; \
			# 将路径分割的 / 替换为 _
			gsub(/\//, "_", info); \
			# 也是整行赋值
			dir=$$0; \
			pkg=""; \
			if($$NF in override) \
				pkg=override[$$NF]; \
			print "$$(eval $$(call PackageDir," info "," dir "," pkg "))"; \
		} ' < $<; \
		true; \
	) > $@.tmp
	# 最终文件长这样
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
