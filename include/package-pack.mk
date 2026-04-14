# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2006-2022 OpenWrt.org

# 打包基础宏，它负责：
# 	包名到文件通配符的推导、旧产物清理
# 	控制字段/脚本的生成（如 postinst、conffiles 等）
# 	带条件的依赖语法解析（在不同配置下裁剪依赖）
# 	构建目标之间的依赖边补全
# 	ELF 运行库依赖的事后校验

ifndef DUMP
  include $(INCLUDE_DIR)/feeds.mk
endif

# 目标机上 opkg 的状态目录，用于安装状态文件（status、lists 等）
IPKG_STATE_DIR:=$(TARGET_DIR)/usr/lib/opkg

# 文本转义，依次转义反引号`、美元$、双引号"、反斜杠\
# 用于写入控制文件（如 Description），避免被 shell/解析器误解释
define description_escape
$(subst `,\`,$(subst $$,\$$,$(subst ",\",$(subst \,\\,$(1)))))
endef

# 生成候选包文件的通配符，返回一个用于匹配产物文件名的“通配符片段”，用在后续 $(wildcard …) 或外部脚本过滤
# 既能覆盖所有以该包名开头的产物文件，又尽量避免误伤同前缀的其它包名（尤其是含连字符和 APK 命名规则差异）
# Generates a make statement to return a wildcard for candidate ipkg files
# 1: package name
define gen_package_wildcard
  # 基础前缀是包名 $(1)
  # 若 ABIV_$(1) 形如 “-…”（filter -%），表示包名里显式带 ABI 后缀，则不再追加通配符，避免误匹配
  # 否则追加一个否定字符类：[^[…]]*，用于“在包名后遇到某些分隔符就进入后缀匹配”
  # 	IPK（非 APK）：追加 [^a-z-]*，即“匹配非字母且非‘-’的字符”，这样能把包名里的连字符视作名字一部分，不把它当作分隔符
  # 	APK：追加 [^a-z]*（不额外排除‘-’），因为 APK 文件名中 name-version 用连字符分隔，需要把 ‘-’ 作为分隔信号
  $(1)$$(if $$(filter -%,$$(ABIV_$(1))),,[^a-z$(if $(CONFIG_USE_APK),,-)])*
endef

# 超长参数处理
# 如果参数个数≥512，用 $(file >tmp,…) 先落盘，再用 xargs 喂给命令，避免命令行过长；否则直接执行
# 1: command and initial arguments，命令
# 2: arguments list，参数列表
# 3: tmp filename，临时文件名
define maybe_use_xargs
  $(if $(word 512,$(2)), \
    $(file >$(3),$(2)) $(XARGS) $(1) < "$(3)"; rm "$(3)", \
    $(1) $(2))
endef

# 删除旧 ipk，如果存在候选文件，删除它们
# 1: package name
# 2: candidate ipk files，候选 ipk 文件列表
define remove_ipkg_files
  $(if $(strip $(2)), \
    $(call maybe_use_xargs,$(SCRIPT_DIR)/ipkg-remove $(1),$(2),$(TMP_DIR)/$(1).in))
endef

# 生成包内控制文件/脚本的通用宏，统一把 Package/xx/{conffiles,preinst,postinst,prerm,postrm,config,…} 写入 CONTROL 目录相应文件，并自动加执行权限
# 1: package name
# 2: variable name
# 3: variable suffix，文件名后缀
# 4: file is a script，是否脚本
define BuildPackVariable
ifdef Package/$(1)/$(2)
  # 为目标添加一个变量
  $$(PACK_$(1)) : VAR_$(2)$(3)=$$(Package/$(1)/$(2))
  # 把该变量导出成可在 shell 中安全读取的变量（逃逸处理）
  $(call shexport,Package/$(1)/$(2))
  $(1)_COMMANDS += echo "$$$$$$$$$(call shvar,Package/$(1)/$(2))" > $(2)$(3); $(if $(4),chmod 0755 $(2)$(3);)
endif
endef

PARENL :=(
PARENR :=)

# 把“条件:值”按冒号切分成“条件 值”两个词
dep_split=$(subst :,$(space),$(1))
# 提取条件词（第1个词），去掉括号和‘!’，用于纯布尔判断
dep_rem=$(subst !,,$(subst $(strip $(PARENL)),,$(subst $(strip $(PARENR)),,$(word 1,$(call dep_split,$(1))))))
# 构造并计算一个“与运算”的表达式
# 把 ‘A&&B&&C’ 切成 A B C，分别取 (CONFIG A)(CONFIG_B) …，再用 $(and …) 求与
dep_and=dep_and_res:=$$(and $(subst $(space),$(comma),$(foreach cond,$(subst &&, ,$(1)),$$(CONFIG_$(cond)))))
# 支持 ‘||’（或）与 ‘&&’（与）组合
# 把 ‘(A&&B||C)’ 拆成 “A&&B”和“C”两个分支，依次 eval dep_and，得到任一分支为真则认为条件成立
dep_confvar=$(strip $(foreach cond,$(subst ||, ,$(call dep_rem,$(1))),$(eval $(call dep_and,$(cond)))$(dep_and_res)))
# 条件成立则返回值，否则空
dep_pos=$(if $(call dep_confvar,$(1)),$(call dep_val,$(1)))
# 条件成立则空，否则返回值（用于有‘!’前缀的否定条件）
dep_neg=$(if $(call dep_confvar,$(1)),,$(call dep_val,$(1)))
# 根据是否包含‘!’选择正/负逻辑
dep_if=$(if $(findstring !,$(1)),$(call dep_neg,$(1)),$(call dep_pos,$(1)))
# 取“条件:值”的“值”（第 2 个词）
dep_val=$(word 2,$(call dep_split,$(1)))
# 去掉以‘@’开头的构建限制标记（如 @TARGET_x86），并去掉‘+’（opkg 用于标注“强制安装”的标志，不参与构建依赖计算）
strip_deps=$(strip $(subst +,,$(filter-out @%,$(1))))
# 遍历依赖列表：
# 	对含冒号的条目（带条件）套 dep_if 解析
# 	对普通条目直接保留
# 	最终得到在当前配置下“实际需要”的依赖集
filter_deps=$(foreach dep,$(call strip_deps,$(1)),$(if $(findstring :,$(dep)),$(call dep_if,$(dep)),$(dep)))

# 生成构建依赖，确保打包 pkgA 前先完成 pkgB/C
define AddDependency
  $$(if $(1),$$(if $(2),$$(foreach pkg,$(1),$$(PACK_$$(pkg))): $$(foreach pkg,$(2),$$(PACK_$$(pkg)))))
endef

# IDEPEND 是提前整理好的“包间依赖边列表”
# IPKGS 是本次要构建的包集合
define FixupReverseDependencies
  # 找出 IDEPEND 中“谁依赖了 $(1)
  DEPS := $$(filter %:$(1),$$(IDEPEND))
  DEPS := $$(patsubst %:$(1),%,$$(DEPS))
  DEPS := $$(filter $$(DEPS),$$(IPKGS))
  # 添加构建依赖
  $(call AddDependency,$$(DEPS),$(1))
endef

define FixupDependencies
  # 找出 IDEPEND 中 $(1) 依赖了谁
  DEPS := $$(filter $(1):%,$$(IDEPEND))
  DEPS := $$(patsubst $(1):%,%,$$(DEPS))
  DEPS := $$(filter $$(DEPS),$$(IPKGS))
  $(call AddDependency,$(1),$$(DEPS))
endef

# 运行库依赖校验（ELF 级）
ifneq ($(PKG_NAME),toolchain)
  define CheckDependencies
	@( \
		rm -f $(PKG_INFO_DIR)/$(1).missing; \
		( \
			export \
				READELF=$(TARGET_CROSS)readelf \
				OBJCOPY=$(TARGET_CROSS)objcopy \
				XARGS="$(XARGS)"; \
			# IDIR_$(1) 是该包的安装镜像目录
			# 对其进行扫描
			$(SCRIPT_DIR)/gen-dependencies.sh "$$(IDIR_$(1))"; \
		) | while read FILE; do \
			grep -qxF "$$$$FILE" $(PKG_INFO_DIR)/$(1).provides || \
				echo "$$$$FILE" >> $(PKG_INFO_DIR)/$(1).missing; \
		done; \
		if [ -f "$(PKG_INFO_DIR)/$(1).missing" ]; then \
			echo "Package $(1) is missing dependencies for the following libraries:" >&2; \
			cat "$(PKG_INFO_DIR)/$(1).missing" >&2; \
			false; \
		fi; \
	)
  endef
endif

# 把一串单词用给定分隔符连接，且在分隔符后保留一个空格
# $(call _addsep,a b c,,) → a, b, c
_addsep=$(word 1,$(1))$(foreach w,$(wordlist 2,$(words $(1)),$(1)),$(strip $(2) $(w)))
# 把“空格+分隔符+空格”清洗成“分隔符+空格”，避免出现 “a , b” 这样的格式
_cleansep=$(subst $(space)$(2)$(space),$(2)$(space),$(1))
# 先 _addsep 再 _cleansep，得到形如 “a, b, c” 的规范逗号分隔列表。
mergelist=$(call _cleansep,$(call _addsep,$(1),$(comma)),$(comma))
# 若值非空，输出 “字段名: 值”，用于控制文件键值对
addfield=$(if $(strip $(2)),$(1): $(2))
# 为了在 eval 或生成文件时输出关键字 define/endef，而不被 make 当场解释
_define=define
_endef=endef

# BuildTarget/ipkg：为包 $(1) 生成目标文件名、安装目录、apk 脚本列表；判定是否需要构建；建立编译/打包/安装到根的依赖边；生成控制脚本与依赖字段；最后调用包的 install 钩子把文件装入镜像
ifeq ($(DUMP),)
  define BuildTarget/ipkg
	# 计算 ABI 后缀（例如 -1 或空），用于包名区分 ABI 兼容性
    ABIV_$(1):=$(call FormatABISuffix,$(1),$(ABI_VERSION))
	# 产物目录（按 feed 分类）
    PDIR_$(1):=$(call FeedPackageDir,$(1))
ifeq ($(CONFIG_USE_APK),)
    PACK_$(1):=$$(PDIR_$(1))/$(1)$$(ABIV_$(1))_$(VERSION)_$(PKGARCH).ipk
else
    PACK_$(1):=$$(PDIR_$(1))/$(1)$$(ABIV_$(1))-$(VERSION).apk
endif
	# ipk 的安装镜像根目录
    IDIR_$(1):=$(PKG_BUILD_DIR)/ipkg-$(PKGARCH)/$(1)
	# apk 的安装镜像根目录
    ADIR_$(1):=$(PKG_BUILD_DIR)/apk-$(PKGARCH)/$(1)
	# conffiles 列表，用于控制文件
    KEEP_$(1):=$(strip $(call Package/$(1)/conffiles))

	# APK 脚本参数
    APK_SCRIPTS_$(1):=

	# 添加 pre-install 与 pre-upgrade 脚本路径
    ifdef Package/$(1)/preinst
      APK_SCRIPTS_$(1)+=--script "pre-install:$$(ADIR_$(1))/preinst"
    endif
	# 总是添加 post-install 与 post-upgrade（脚本文件稍后生成）
    APK_SCRIPTS_$(1)+=--script "post-install:$$(ADIR_$(1))/post-install"

    ifdef Package/$(1)/preinst
      APK_SCRIPTS_$(1)+=--script "pre-upgrade:$$(ADIR_$(1))/pre-upgrade"
    endif
    APK_SCRIPTS_$(1)+=--script "post-upgrade:$$(ADIR_$(1))/post-upgrade"

    APK_SCRIPTS_$(1)+=--script "pre-deinstall:$$(ADIR_$(1))/pre-deinstall"
    ifdef Package/$(1)/postrm
      APK_SCRIPTS_$(1)+=--script "post-deinstall:$$(ADIR_$(1))/postrm"
    endif

	# 确定变体
    TARGET_VARIANT:=$$(if $(ALL_VARIANTS),$$(if $$(VARIANT),$$(filter-out *,$$(VARIANT)),$(firstword $(ALL_VARIANTS))))
    ifeq ($(BUILD_VARIANT),$$(if $$(TARGET_VARIANT),$$(TARGET_VARIANT),$(BUILD_VARIANT)))
    do_install=
    ifdef Package/$(1)/install
      do_install=yes
    endif
    ifdef Package/$(1)/install-overlay
      do_install=yes
    endif
    ifdef do_install
	  # 包未启用
      ifneq ($(CONFIG_PACKAGE_$(1))$(DEVELOPER),)
	    # 登记到将要构建的包列表
        IPKGS += $(1)
		# 注册编译阶段对“成品包、provides 文件、安装镜像 stamp”的依赖
        $(_pkg_target)compile: $$(PACK_$(1)) $(PKG_INFO_DIR)/$(1).provides $(PKG_BUILD_DIR)/.pkgdir/$(1).installed
		# 安装准备前必须先生成包文件
        prepare-package-install: $$(PACK_$(1))
		# 编译阶段还要把镜像内容同步到 STAGING_DIR_ROOT（供后续包使用）。
        compile: $(STAGING_DIR_ROOT)/stamp/.$(1)_installed
      else
        $(if $(CONFIG_PACKAGE_$(1)),$$(info WARNING: skipping $(1) -- package not selected))
      endif

      .PHONY: $(PKG_INSTALL_STAMP).$(1)
      ifeq ($(CONFIG_PACKAGE_$(1)),y)
	    # 写入包名到全局安装标记文件，便于统计/追踪
        compile: $(PKG_INSTALL_STAMP).$(1)
      endif
      $(PKG_INSTALL_STAMP).$(1): prepare-package-install
		echo "$(1)" >> $(PKG_INSTALL_STAMP)
    else
	  # 打印 warning，说明未选中或没有 install 段
      $(if $(CONFIG_PACKAGE_$(1)),$$(warning WARNING: skipping $(1) -- package has no install section))
    endif
    endif

	# 对包写的 DEPENDS 做一次修正（比如把内建库名调整为正确虚包、追加工具链依赖等）
    DEPENDS:=$(call PKG_FIXUP_DEPENDS,$(1),$(DEPENDS))
	# 过滤掉不满足配置的条件依赖，去掉构建限制（@）等
    IDEPEND_$(1):=$$(call filter_deps,$$(DEPENDS))
	# 记录“包间依赖边”（形如 foo:bar）
    IDEPEND += $$(patsubst %,$(1):%,$$(IDEPEND_$(1)))
	# 把 IDEPEND 中的边落实到 make 目标依赖上，确保依赖包先打出来（或信息已就绪）
    $(FixupDependencies)
    $(FixupReverseDependencies)

	# 生成控制文件脚本与 conffiles
    $(eval $(call BuildPackVariable,$(1),conffiles))
    $(eval $(call BuildPackVariable,$(1),preinst,,1))
    $(eval $(call BuildPackVariable,$(1),postinst,-pkg,1))
    $(eval $(call BuildPackVariable,$(1),prerm,-pkg,1))
    $(eval $(call BuildPackVariable,$(1),postrm,,1))

	# 使用目标工具链/辅助工具
    $(PKG_BUILD_DIR)/.pkgdir/$(1).installed : export PATH=$$(TARGET_PATH_PKG)
    $(PKG_BUILD_DIR)/.pkgdir/$(1).installed: $(STAMP_BUILT)
	rm -rf $$@ $(PKG_BUILD_DIR)/.pkgdir/$(1)
	mkdir -p $(PKG_BUILD_DIR)/.pkgdir/$(1)
	# 调用包的钩子
	$(call Package/$(1)/install,$(PKG_BUILD_DIR)/.pkgdir/$(1))
	$(call Package/$(1)/install_lib,$(PKG_BUILD_DIR)/.pkgdir/$(1))
	# 生成 stamp
	touch $$@

	# 同步到 STAGING_DIR_ROOT
    $(STAGING_DIR_ROOT)/stamp/.$(1)_installed: $(PKG_BUILD_DIR)/.pkgdir/$(1).installed
	mkdir -p $(STAGING_DIR_ROOT)/stamp
	# 若 ABI_VERSION 变化，则更新，并同步到 $(PROVIDES) 的其它虚包名上
	$(if $(ABI_VERSION),echo '$(ABI_VERSION)' | cmp -s - $(PKG_INFO_DIR)/$(1).version || { \
		echo '$(ABI_VERSION)' > $(PKG_INFO_DIR)/$(1).version; \
		$(foreach pkg,$(filter-out $(1),$(PROVIDES)), \
			cp $(PKG_INFO_DIR)/$(1).version $(PKG_INFO_DIR)/$(pkg).version; \
		) \
	} )
	# 把 .pkgdir/$(1) 的内容拷贝进 STAGING_DIR_ROOT，locked 用于避免并发冲突
	$(call locked,$(CP) $(PKG_BUILD_DIR)/.pkgdir/$(1)/. $(STAGING_DIR_ROOT)/,root-copy)
	touch $$@

	# 从 IDEPEND_$(1) 去掉 @ 限制项；对每个依赖追加 ABI 后缀；再用 mergelist 变成 “a (abi), b (abi)” 格式
    Package/$(1)/DEPENDS := $$(call mergelist,$$(foreach dep,$$(filter-out @%,$$(IDEPEND_$(1))),$$(dep)$$(call GetABISuffix,$$(dep))))
	# 如果定义了 EXTRA_DEPENDS，则把它们加到最前面（并用逗号分隔）
    ifneq ($$(EXTRA_DEPENDS),)
      Package/$(1)/DEPENDS := $$(EXTRA_DEPENDS)$$(if $$(Package/$(1)/DEPENDS),$$(comma) $$(Package/$(1)/DEPENDS))
    endif

# 定义一个多行变量：Package/$(1)/CONTROL
# 它是 ipk 控制文件“control”的内容模板；对 apk 则转化为 mkpkg 的 --info 字段。
$(_define) Package/$(1)/CONTROL
# 包名附带 ABI 后缀（如 foo-2），用于区分 ABI 变更
Package: $(1)$$(ABIV_$(1))
Version: $(VERSION)
# addfield 仅在值非空时输出一行
$$(call addfield,Depends,$$(Package/$(1)/DEPENDS)
# mergelist 把空白分隔列表规整为 “a, b, c”的逗号串
)$$(call addfield,Conflicts,$$(call mergelist,$(CONFLICTS))
# filter-out 当前包自身，避免自提供重复
# 若有 ABIV 后缀，会同时加入：
# 	原始 PROVIDES
# 	$(1)（不带后缀，便于虚包名兼容）
# 	每个 provide 再附加 ABI 后缀（provide-2）
)$$(call addfield,Provides,$$(call mergelist,$$(filter-out $(1)$$(ABIV_$(1)),$(PROVIDES)$$(if $$(ABIV_$(1)), $(1) $(foreach provide,$(PROVIDES),$(provide)$$(ABIV_$(1))))))
)$$(call addfield,Alternatives,$$(call mergelist,$(ALTERNATIVES))
# 以下大多来自包定义变量
)$$(call addfield,Source,$(SOURCE)
)$$(call addfield,SourceName,$(PKG_NAME)
)$$(call addfield,License,$(LICENSE)
)$$(call addfield,LicenseFiles,$(LICENSE_FILES)
)$$(call addfield,Section,$(SECTION)
# 指定安装时需要创建的用户/组（OpenWrt 扩展）
)$$(call addfield,Require-User,$(USERID)
# 为可复现构建注入源时间戳
)$$(call addfield,SourceDateEpoch,$(PKG_SOURCE_DATE_EPOCH)
)$$(call addfield,URL,$(URL)
)$$(if $$(ABIV_$(1)),ABIVersion: $$(ABIV_$(1))
)$(if $(PKG_CPE_ID),CPE-ID: $(PKG_CPE_ID)
# 从 $(PKG_FLAGS) 推导
)$(if $(filter hold,$(PKG_FLAGS)),Status: unknown hold not-installed
)$(if $(filter essential,$(PKG_FLAGS)),Essential: yes
)$(if $(MAINTAINER),Maintainer: $(MAINTAINER)
)Architecture: $(PKGARCH)
# 这里先写 0，实际 ipkg-build 会重新计算覆盖
Installed-Size: 0
$(_endef)

	# 把上一步拼好的控制头与描述传给后续脚本
    $$(PACK_$(1)) : export CONTROL=$$(Package/$(1)/CONTROL)
    $$(PACK_$(1)) : export DESCRIPTION=$$(Package/$(1)/description)
	# 确保工具使用目标版/打包版
    $$(PACK_$(1)) : export PATH=$$(TARGET_PATH_PKG)
    $$(PACK_$(1)) : export PKG_SOURCE_DATE_EPOCH:=$(PKG_SOURCE_DATE_EPOCH)
    $$(PACK_$(1)) : export SOURCE_DATE_EPOCH:=$(PKG_SOURCE_DATE_EPOCH)
	# provides 和 $(PACK_$(1)) 都依赖 $(STAMP_BUILT) 与 package-pack.mk，以确保先构建完文件内容再打包
    $(PKG_INFO_DIR)/$(1).provides $$(PACK_$(1)): $(STAMP_BUILT) $(INCLUDE_DIR)/package-pack.mk
	# 清空包镜像根目录
	rm -rf $$(IDIR_$(1))
	# 删除旧包文件
ifeq ($$(CONFIG_USE_APK),)
	$$(call remove_ipkg_files,$(1),$$(call opkg_package_files,$(call gen_package_wildcard,$(1))))
else
	$$(call remove_ipkg_files,$(1),$$(call apk_package_files,$(call gen_package_wildcard,$(1))))
endif
	mkdir -p $(PACKAGE_DIR) $$(IDIR_$(1)) $(PKG_INFO_DIR)
	# 调用钩子填充镜像
	$(call Package/$(1)/install,$$(IDIR_$(1)))
	$(if $(Package/$(1)/install-overlay),mkdir -p $(PACKAGE_DIR) $$(IDIR_$(1))/rootfs-overlay)
	$(call Package/$(1)/install-overlay,$$(IDIR_$(1))/rootfs-overlay)
	# 清理 VCS/备份垃圾文件
	-find $$(IDIR_$(1)) -name 'CVS' -o -name '.svn' -o -name '.#*' -o -name '*~'| $(XARGS) rm -rf
	@( \
		# 收集本包内文件名为 lib*.so* 或 *.ko 的基名（用 awk -F/ '{print $$NF}'），表示本包“直接提供”的共享库/内核模块名
		find $$(IDIR_$(1)) -name lib\*.so\* -or -name \*.ko | awk -F/ '{ print $$$$NF }'; \
		# 加上每个依赖包的 .provides 文件内容（递归汇总间接提供者）
		for file in $$(patsubst %,$(PKG_INFO_DIR)/%.provides,$$(IDEPEND_$(1))); do \
			if [ -f "$$$$file" ]; then \
				cat $$$$file; \
			fi; \
		done; $(Package/$(1)/extra_provides) \ # 加上包自定义的 extra_provides
		# 全部 sort -u 去重后写入 .provides
	) | sort -u > $(PKG_INFO_DIR)/$(1).provides
	# 若 $(PROVIDES) 有虚包名，为每个虚包名复制一份 .provides
	$(if $(PROVIDES),@for pkg in $(filter-out $(1),$(PROVIDES)); do cp $(PKG_INFO_DIR)/$(1).provides $(PKG_INFO_DIR)/$$$$pkg.provides; done)
	# 扫描 $$(IDIR_$(1)) 的 ELF NEEDED，核对是否由依赖链中的包提供；缺失时报错，避免安装后缺库
	$(CheckDependencies)

	# 精简二进制（strip 符号、压缩 Lua、去除不必要的 RPATH 等，具体由工具链配置决定）
	$(RSTRIP) $$(IDIR_$(1))

	# 生成 CONTROL/files-sha256sum，排除 CONTROL/ 下文件，使用 MKHASH sha256
    ifneq ($$(CONFIG_IPK_FILES_CHECKSUMS),)
	(cd $$(IDIR_$(1)); \
		( \
			find . -type f \! -path ./CONTROL/\* -exec $(MKHASH) sha256 -n \{\} \; 2> /dev/null | \
			sed 's|\([[:blank:]]\)\./| \1/|' > $$(IDIR_$(1))/CONTROL/files-sha256sum \
		) || true \
	)
    endif

	# 保留配置文件 keep.d
	# 检查列出的 conffiles 是否实际存在于 IDIR；不存在的路径会被加入 /lib/upgrade/keep.d/$(1)，以便系统升级时保留这些路径
    ifneq ($$(KEEP_$(1)),)
		@( \
			keepfiles=""; \
			for x in $$(KEEP_$(1)); do \
				[ -f "$$(IDIR_$(1))/$$$$x" ] || keepfiles="$$$${keepfiles:+$$$$keepfiles }$$$$x"; \
			done; \
			[ -z "$$$$keepfiles" ] || { \
				mkdir -p $$(IDIR_$(1))/lib/upgrade/keep.d; \
				for x in $$$$keepfiles; do echo $$$$x >> $$(IDIR_$(1))/lib/upgrade/keep.d/$(1); done; \
			}; \
		)
    endif

	$(INSTALL_DIR) $$(PDIR_$(1))/tmp

# IPK 打包分支
ifeq ($(CONFIG_USE_APK),)
	mkdir -p $$(IDIR_$(1))/CONTROL
	(cd $$(IDIR_$(1))/CONTROL; \
		( \
			echo "$$$$CONTROL"; \
			# 首行打印 “Description: ”；后续用 sed 把描述文本的行首缩进成单空格，符合 Debian control 的多行描述规范
			printf "Description: "; echo "$$$$DESCRIPTION" | sed -e 's,^[[:space:]]*, ,g'; \
		) > control; \
		chmod 644 control; \
		# 写入 postinst
		( \
			echo "#!/bin/sh"; \
			echo "[ \"\$$$${IPKG_NO_SCRIPT}\" = \"1\" ] && exit 0"; \
			echo "[ -s "\$$$${IPKG_INSTROOT}/lib/functions.sh" ] || exit 0"; \
			echo ". \$$$${IPKG_INSTROOT}/lib/functions.sh"; \
			echo "default_postinst \$$$$0 \$$$$@"; \
		) > postinst; \
		# 写入 prerm
		( \
			echo "#!/bin/sh"; \
			echo "[ -s "\$$$${IPKG_INSTROOT}/lib/functions.sh" ] || exit 0"; \
			echo ". \$$$${IPKG_INSTROOT}/lib/functions.sh"; \
			echo "default_prerm \$$$$0 \$$$$@"; \
		) > prerm; \
		chmod 0755 postinst prerm; \
		# 追加包的命令，来自前面 BuildPackVariable）
		$($(1)_COMMANDS) \
	)

	# 构建 ipk
	# fakeroot 确保打包时能记录合理的文件属主属组/权限而无需真正 root
	$(FAKEROOT) $(STAGING_DIR_HOST)/bin/bash $(SCRIPT_DIR)/ipkg-build -m "$(FILE_MODES)" $$(IDIR_$(1)) $$(PDIR_$(1))
else
	# APK 打包分支
	# 脚本与 apk 专用元数据暂存
	mkdir -p $$(ADIR_$(1))/
	# apk 元数据存放位置（list、conffiles、alternatives、rusers）
	mkdir -p $$(IDIR_$(1))/lib/apk/packages/

	(cd $$(ADIR_$(1)); $($(1)_COMMANDS))

	( \
		echo "#!/bin/sh"; \
		echo "[ \"\$$$${IPKG_NO_SCRIPT}\" = \"1\" ] && exit 0"; \
		echo "[ -s "\$$$${IPKG_INSTROOT}/lib/functions.sh" ] || exit 0"; \
		echo ". \$$$${IPKG_INSTROOT}/lib/functions.sh"; \
		echo 'export root="$$$${IPKG_INSTROOT}"'; \
		echo 'export pkgname="$(1)"'; \
		echo "add_group_and_user"; \
		echo "default_postinst"; \
		# 如存在自定义 postinst-pkg，用 sed -z 去除文件开头的空白后追加
		[ ! -f $$(ADIR_$(1))/postinst-pkg ] || sed -z 's/^\s*#!/#!/' "$$(ADIR_$(1))/postinst-pkg"; \
	) > $$(ADIR_$(1))/post-install;

    ifdef Package/$(1)/preinst
	( \
		echo "#!/bin/sh"; \
		echo 'export PKG_UPGRADE=1'; \
		[ ! -f $$(ADIR_$(1))/preinst ] || sed -z 's/^\s*#!/#!/' "$$(ADIR_$(1))/preinst"; \
	) > $$(ADIR_$(1))/pre-upgrade;
    endif

	( \
		echo "#!/bin/sh"; \
		echo 'export PKG_UPGRADE=1'; \
		[ ! -f $$(ADIR_$(1))/post-install ] || sed -z 's/^\s*#!/#!/' "$$(ADIR_$(1))/post-install"; \
	) > $$(ADIR_$(1))/post-upgrade;

	( \
		echo "#!/bin/sh"; \
		echo "[ -s "\$$$${IPKG_INSTROOT}/lib/functions.sh" ] || exit 0"; \
		echo ". \$$$${IPKG_INSTROOT}/lib/functions.sh"; \
		echo 'export root="$$$${IPKG_INSTROOT}"'; \
		echo 'export pkgname="$(1)"'; \
		echo "default_prerm"; \
		[ ! -f $$(ADIR_$(1))/prerm-pkg ] || sed -z 's/^\s*#!/#!/' "$$(ADIR_$(1))/prerm-pkg"; \
	) > $$(ADIR_$(1))/pre-deinstall;

	# postrm 若存在，先用 sed -zi 去除开头空白与 shebang 对齐
	[ ! -f $$(ADIR_$(1))/postrm ] || sed -zi 's/^\s*#!/#!/' "$$(ADIR_$(1))/postrm";

	# 若定义 USERID，则写入 $(1).rusers
	if [ -n "$(USERID)" ]; then echo $(USERID) > $$(IDIR_$(1))/lib/apk/packages/$(1).rusers; fi;
	# 若定义 ALTERNATIVES，则写入 $(1).alternatives。
	if [ -n "$(ALTERNATIVES)" ]; then echo $(ALTERNATIVES) > $$(IDIR_$(1))/lib/apk/packages/$(1).alternatives; fi;
	# 在 IDIR 内生成完整文件列表（以 / 为前缀），保存为 $(1).list
	(cd $$(IDIR_$(1)) && find . -type f,l -printf "/%P\n" | sort > $(TMP_DIR)/$(1).list && mv $(TMP_DIR)/$(1).list $$(IDIR_$(1))/lib/apk/packages/$(1).list)
	# Move conffiles to IDIR and build conffiles_static with csums
	# 优先使用 ADIR/conffiles → 移动到 IDIR 的 .conffiles，并为每个条目生成 sha256 → .conffiles_static
	if [ -f $$(ADIR_$(1))/conffiles ]; then \
		mv -f $$(ADIR_$(1))/conffiles $$(IDIR_$(1))/lib/apk/packages/$(1).conffiles; \
		for file in $$$$(cat $$(IDIR_$(1))/lib/apk/packages/$(1).conffiles); do \
			[ -f $$(IDIR_$(1))/$$$$file ] || continue; \
			csum=$$$$($(MKHASH) sha256 $$(IDIR_$(1))/$$$$file); \
			echo $$$$file $$$$csum >> $$(IDIR_$(1))/lib/apk/packages/$(1).conffiles_static; \
		done; \
	fi

	# 若 IDIR/CONTROL/conffiles 存在（比如包手工追加），合并到上述两个文件后删除 CONTROL/conffiles。
	# Some package (base-files) manually append stuff to conffiles
	# Append stuff from it and delete the CONTROL directory since everything else should be migrated
	if [ -f $$(IDIR_$(1))/CONTROL/conffiles ]; then \
		echo $$$$(IDIR_$(1))/CONTROL/conffiles >> $$(IDIR_$(1))/lib/apk/packages/$(1).conffiles; \
		for file in $$$$(cat $$(IDIR_$(1))/CONTROL/conffiles); do \
			[ -f $$(IDIR_$(1))/$$$$file ] || continue; \
			csum=$$$$($(MKHASH) sha256 $$(IDIR_$(1))/$$$$file); \
			echo $$$$file $$$$csum >> $$(IDIR_$(1))/lib/apk/packages/$(1).conffiles_static; \
		done; \
		rm -rf $$(IDIR_$(1))/CONTROL/conffiles; \
	fi

	# CONTROL 目录清理检查：若非空则报错退出，确保所有控制内容都迁移到了 apk 元数据位置
	if [ -z "$$$$(ls -A $$(IDIR_$(1))/CONTROL 2>/dev/null)" ]; then \
		rm -rf $$(IDIR_$(1))/CONTROL; \
	else \
		echo "CONTROL directory $$(IDIR_$(1))/CONTROL is not empty! This is not right and should be checked!" >&2; \
		exit 1; \
	fi

	# 构建 APK
	$(FAKEROOT) $(STAGING_DIR_HOST)/bin/apk mkpkg \
	  # 通过 --info 注入字段
	  --info "name:$(1)$$(ABIV_$(1))" \
	  --info "version:$(VERSION)" \
	  $$(if $$(ABIV_$(1)),--info "tags:openwrt:abiversion=$$(ABIV_$(1))") \
	  --info "description:$$(call description_escape,$$(strip $$(Package/$(1)/description)))" \
	  $(if $(findstring all,$(PKGARCH)),--info "arch:noarch",--info "arch:$(PKGARCH)") \
	  --info "license:$(LICENSE)" \
	  --info "origin:$(SOURCE)" \
	  --info "url:$(URL)" \
	  --info "maintainer:$(MAINTAINER)" \
	  # 为每个提供者生成 “name=version”，若存在 ABIV 也为带后缀的 provider 生成带版本的提供
	  --info "provides:$$(foreach prov,\
			$$(filter-out $(1)$$(ABIV_$(1)), \
			$(PROVIDES)$$(if $$(ABIV_$(1)), \
				$(1)=$(VERSION) $(foreach provide, \
					$(PROVIDES), \
					$(provide)$$(ABIV_$(1))=$(VERSION) \
				) \
			) \
		), \
		$$(prov) )" \
	  # 默认变体优先级 100；若只是 PROVIDES 虚包，优先级 1
	  $(if $(DEFAULT_VARIANT),--info "provider-priority:100",$(if $(PROVIDES),--info "provider-priority:1")) \
	  $$(APK_SCRIPTS_$(1)) \
	  # 把 Package/$(1)/DEPENDS 清除逗号/空格/括号后按空格展开为 apk 依赖列表
	  --info "depends:$$(foreach depends,$$(subst $$(comma),$$(space),$$(subst $$(space),,$$(subst $$(paren_right),,$$(subst $$(paren_left),,$$(Package/$(1)/DEPENDS))))),$$(depends))" \
	  --files "$$(IDIR_$(1))" \
	  --output "$$(PACK_$(1))"
endif

	@[ -f $$(PACK_$(1)) ]

	# 清理目标
    $(1)-clean:
ifeq ($(CONFIG_USE_APK),)
	$$(call remove_ipkg_files,$(1),$$(call opkg_package_files,$(call gen_package_wildcard,$(1))))
else
	$$(call remove_ipkg_files,$(1),$$(call apk_package_files,$(call gen_package_wildcard,$(1))))
endif


    clean: $(1)-clean

  endef
endif
