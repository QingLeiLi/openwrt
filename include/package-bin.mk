# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2007-2020 OpenWrt.org

ifeq ($(DUMP),)
  define BuildTarget/bin
    # 计算变体
    # 这个 if 没有 else，当未定义 ALL_VARIANTS 时，TARGET_VARIANT 为空
    TARGET_VARIANT=$(if
      $(ALL_VARIANTS),
      $(if
        $(VARIANT),
        # * 在这里没有特殊含义，只是普通字符串
        # 这里处理的是 VARIANT 为 "*" 的场景，将 * 过滤掉，得到空字符串，含义是不限制变体
        # "*"" => ""
        # "foo * bar" => "foo bar"   // 这个是因为 filter-out 会用空白符切开字符串，执行 filter，再合并起来，* 被单独切出来，会被匹配到
        # "foo*bar" => "foo*bar"    // 这个是因为没有空格，* 不会被单独切出来，而表达式也没加通配符 %，* 不会被移除
        $(filter-out *,$(VARIANT)),
        # 未显式指定 VARIANT 时，选择 ALL_VARIANTS 的第一个作为默认变体
        $(firstword $(ALL_VARIANTS))
      )
    )
    # 当 BUILD_VARIANT 与之匹配时才定义规则，避免多变体包重复生成目标
    # TARGET_VARIANT 没值，是 空字符串 和 TARGET_VARIANT（空字符串） 比较
    # TARGET_VARIANT 有值，是 BUILD_VARIANT 和 TARGET_VARIANT 比较
    ifeq ($(if $(TARGET_VARIANT),$(BUILD_VARIANT)),$(TARGET_VARIANT))
    # 没定义 install 命令的，应该都没有文件生成，也就不需要拷贝 bin 了
    ifdef Package/$(1)/install
      # CONFIG_PACKAGE_xx 是在 .config 中选中的包才会设置这个变量，起到开关的作用，只有有这个变量，才启用这个包
      # DEVELOPER=1 时，即使包没在 .config 里选中，也会跑 install 并导出到 bin，方便开发调试安装规则
      ifneq ($(CONFIG_PACKAGE_$(1))$(DEVELOPER),)
        $(_pkg_target)compile: $(PKG_BUILD_DIR)/.pkgdir/$(1).installed
        compile: install-bin-$(1)
      else
        compile: $(1)-disabled
        $(1)-disabled:
		@echo "WARNING: skipping $(1) -- package not selected" >&2
      endif
    endif
    endif

    $(PKG_BUILD_DIR)/.pkgdir/$(1).installed: $(STAMP_BUILT)
		rm -rf $(PKG_BUILD_DIR)/.pkgdir/$(1) $$@
		mkdir -p $(PKG_BUILD_DIR)/.pkgdir/$(1)
		$(call Package/$(1)/install,$(PKG_BUILD_DIR)/.pkgdir/$(1))
		touch $$@

    install-bin-$(1): $(PKG_BUILD_DIR)/.pkgdir/$(1).installed
	rm -rf $(BIN_DIR)/$(1)
  # rmdir 前面有 “-”，失败不报错
  # 只有空目录会被 rmdir 成功，下面检查 -d 是否为目录，如果为空，会被删掉，跳过复制
	-rmdir $(PKG_BUILD_DIR)/.pkgdir/$(1) >/dev/null 2>/dev/null
	if [ -d $(PKG_BUILD_DIR)/.pkgdir/$(1) ]; then \
		$(INSTALL_DIR) $(BIN_DIR)/$(1) && \
		$(CP) $(PKG_BUILD_DIR)/.pkgdir/$(1)/. $(BIN_DIR)/$(1)/; \
	fi

    # 定义清理命令 和 依赖
    clean-$(1):
	  rm -rf $(BIN_DIR)/$(1)

    clean: clean-$(1)
    .PHONY: install-bin-$(1)
  endef
endif
