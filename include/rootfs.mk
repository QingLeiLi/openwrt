ifdef CONFIG_USE_MKLIBS
  define mklibs
	# 清理临时目录
	rm -rf $(TMP_DIR)/mklibs-progs $(TMP_DIR)/mklibs-out
	# first find all programs and add them to the mklibs list
	# 在staging目录中查找所有可执行文件（权限包含执行位）
	find $(STAGING_DIR_ROOT) -type f -perm /100 -exec \
		# 使用 file 命令检查文件类型
		file -r -N -F '' {} + | \
		# 用 awk 过滤出动态链接的可执行文件，将结果保存到 mklibs-progs 文件
		awk ' /executable.*dynamically/ { print $$1 }' > $(TMP_DIR)/mklibs-progs
	# find all loadable objects that are not regular libraries and add them to the list as well
	# 查找所有 .so* 文件（共享库）
	find $(STAGING_DIR_ROOT) -type f -name \*.so\* -exec \
		# 使用 file 命令检查文件类型
		file -r -N -F '' {} + | \
		# 过滤出共享对象文件，保存到 mklibs-libs 文件
		awk ' /shared object/ { print $$1 }' > $(TMP_DIR)/mklibs-libs
	# 创建输出目录
	mkdir -p $(TMP_DIR)/mklibs-out
	# -D 表示调试模式
	$(STAGING_DIR_HOST)/bin/mklibs -D \
		# 指定输出目录
		-d $(TMP_DIR)/mklibs-out \
		# 设置系统根目录
		--sysroot $(STAGING_DIR_ROOT) \
		`cat $(TMP_DIR)/mklibs-libs | sed 's:/*[^/]\+/*$$::' | uniq | sed 's:^$(STAGING_DIR_ROOT):-L :'` \
		# 指定动态链接器，自动查找各种类型的ld（uClibc、glibc、musl等）
		--ldlib $(patsubst $(STAGING_DIR_ROOT)/%,/%,$(firstword $(wildcard \
			$(foreach name,ld-uClibc.so.* ld-linux.so.* ld-*.so ld-musl-*.so.*, \
			  $(STAGING_DIR_ROOT)/lib/$(name) \
			)))) \
		# 指定目标架构
		--target $(REAL_GNU_TARGET_NAME) \
		# 传入所有程序和库文件列表
		`cat $(TMP_DIR)/mklibs-progs $(TMP_DIR)/mklibs-libs` 2>&1
	# 对生成的库文件执行strip操作，去除调试符号以减小文件大小
	$(RSTRIP) $(TMP_DIR)/mklibs-out
	# 遍历所有优化后的 .so.* 文件
	for lib in `ls $(TMP_DIR)/mklibs-out/*.so.* 2>/dev/null`; do \
		# 提取文件名（去掉路径）
		LIB="$${lib##*/}"; \
		# 在目标系统的 /lib 或 /usr/lib 中查找对应的库文件
		DEST="`ls "$(1)/lib/$$LIB" "$(1)/usr/lib/$$LIB" 2>/dev/null`"; \
		# 找不到目标文件就跳过
		[ -n "$$DEST" ] || continue; \
		echo "Copying stripped library $$lib to $$DEST"; \
		# 替换原来的库文件
		cp "$$lib" "$$DEST" || exit 1; \
	done
  endef
endif

# where to build (and put) .ipk packages
opkg = \
  IPKG_NO_SCRIPT=1 \
  IPKG_INSTROOT=$(1) \
  TMPDIR=$(1)/tmp \
  $(STAGING_DIR_HOST)/bin/opkg \
	--offline-root $(1) \
	--force-postinstall \
	--add-dest root:/ \
	--add-arch all:100 \
	--add-arch $(if $(ARCH_PACKAGES),$(ARCH_PACKAGES),$(BOARD)):200

apk = \
  IPKG_INSTROOT=$(1) \
  $(FAKEROOT) $(STAGING_DIR_HOST)/bin/apk \
	--root $(1) \
	--keys-dir $(if $(APK_KEYS),$(APK_KEYS),$(TOPDIR)) \
	--no-logfile \
	--preserve-env

TARGET_DIR_ORIG := $(TARGET_ROOTFS_DIR)/root.orig-$(BOARD)

ifdef CONFIG_CLEAN_IPKG
  define clean_ipkg
	-find $(1)/usr/lib/opkg/info -type f -and -not -name '*.control' -delete
	-sed -i -ne '/^Require-User: /p' $(1)/usr/lib/opkg/info/*.control
	awk ' \
		BEGIN { conffiles = 0; print "Conffiles:" } \
		/^Conffiles:/ { conffiles = 1; next } \
		!/^ / { conffiles = 0; next } \
		conffiles == 1 { print } \
	' $(1)/usr/lib/opkg/status >$(1)/usr/lib/opkg/status.new
	mv $(1)/usr/lib/opkg/status.new $(1)/usr/lib/opkg/status
	-find $(1)/usr/lib/opkg -empty -delete
  endef
endif

# 准备根文件系统（rootfs）
define prepare_rootfs
	# 复制基础文件系统
	# 如果第2个参数存在且是目录，就将其内容复制到第1个参数指定的目录
	$(if $(2),@if [ -d '$(2)' ]; then \
		$(call file_copy,$(2)/.,$(1)); \
	fi)
	@mkdir -p $(1)/etc/rc.d
	@mkdir -p $(1)/var/lock
	# @ 表示开始一个子shell执行环境
	@( \
		# 切换到根文件系统目录
		cd $(1); \
		# 根据包管理器类型分别执行逻辑
		if [ -n "$(CONFIG_USE_APK)" ]; then \
			# 设置安装后脚本路径为APK格式
			IPKG_POSTINST_PATH=./lib/apk/db/*.post-install; \
			# 从tar包中提取安装后脚本
			$(STAGING_DIR_HOST)/bin/tar -C ./lib/apk/db/ -xf ./lib/apk/db/scripts.tar --wildcards "*.post-install"; \
		else \
			IPKG_POSTINST_PATH=./usr/lib/opkg/info/*.postinst; \
		fi; \
		# 遍历所有安装后脚本并执行
		for script in $$IPKG_POSTINST_PATH; do \
			IPKG_INSTROOT=$(1) $$(command -v bash) $$script; \
			# 检查脚本执行是否成功
			ret=$$?; \
			if [ $$ret -ne 0 ]; then \
				echo "postinst script $$script has failed with exit code $$ret" >&2; \
				exit 1; \
			fi; \
			# 从tar包中删除已执行的脚本（仅APK格式）
			[ -n "$(CONFIG_USE_APK)" ] && $(STAGING_DIR_HOST)/bin/tar --delete -f ./lib/apk/db/scripts.tar $$(basename $$script); \
		done; \
		# 如果不使用APK（即使用OPKG）
		if [ -z "$(CONFIG_USE_APK)" ]; then \
			# 使用 awk 修改包状态文件，将"user"状态改为"ok"
			$(if $(IB),,awk -i inplace \
				'/^Status:/ { \
					if ($$3 == "user") { $$3 = "ok" } \
					else { sub(/,\<user\>|\<user\>,/, "", $$3) } \
				}1' $(1)/usr/lib/opkg/status) ; \
			# 如果设置了SOURCE_DATE_EPOCH，则更新安装时间
			$(if $(SOURCE_DATE_EPOCH),sed -i "s/Installed-Time: .*/Installed-Time: $(SOURCE_DATE_EPOCH)/" $(1)/usr/lib/opkg/status ;) \
		fi; \
		# 处理系统服务，遍历 /etc/init.d/ 中的启动脚本，根据第3个参数决定启用或禁用服务
		for script in ./etc/init.d/*; do \
			# 检查脚本是否为OpenWrt格式的启动脚本
			grep '#!/bin/sh /etc/rc.common' $$script >/dev/null || continue; \
			# 如果脚本名不在第3个参数的禁用列表中，则启用服务；否则禁用
			if ! echo " $(3) " | grep -q " $$(basename $$script) "; then \
				IPKG_INSTROOT=$(1) $$(command -v bash) ./etc/rc.common $$script enable; \
				echo "Enabling" $$(basename $$script); \
			else \
				IPKG_INSTROOT=$(1) $$(command -v bash) ./etc/rc.common $$script disable; \
				echo "Disabling" $$(basename $$script); \
			fi; \
		done || true \
	)

	# 删除版本控制文件（CVS、SVN、Git）
	# - 表示即使命令失败也继续执行
	@-find $(1) -name CVS -o -name .svn -o -name .git -o -name '.#*' | $(XARGS) rm -rf
	rm -rf \
		# 删除boot目录（嵌入式系统通常不需要）
		$(1)/boot \
		$(1)/tmp/* \
		# 删除安装后脚本
		$(1)/lib/apk/db/*.post-install* \
		# 删除安装后脚本
		$(1)/usr/lib/opkg/info/*.postinst* \
		# 清理包管理器缓存
		$(1)/usr/lib/opkg/lists/* \
		# 清理锁文件
		$(1)/var/lock/*.lock
	# 清理包管理器数据
	$(call clean_ipkg,$(1))
	$(call mklibs,$(1))
	# 统一所有文件的时间戳
	$(if $(SOURCE_DATE_EPOCH),find $(1)/ -mindepth 1 -execdir touch -hcd "@$(SOURCE_DATE_EPOCH)" "{}" +)
endef
