# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2007 OpenWrt.org

# CURDIR是make的内嵌变量， 为当前目录
TOPDIR:=${CURDIR}
# https://unix.stackexchange.com/a/87748
LC_ALL:=C
LANG:=C
TZ:=UTC
export TOPDIR LC_ALL LANG TZ

empty:=
space:= $(empty) $(empty)
$(if $(findstring $(space),$(TOPDIR)),$(error ERROR: The path to the OpenWrt directory must not include any spaces))

# 定义一个空的目标，只是为了在没有目标的时候执行这个
world:

# grep -e 表示是正则，满足任一 -e 条件的才会被打印出来
# ➜ echo "test1111\ntest2222\ntest3333\ntest444" | grep -e "test2" -e "test4"
# test2222
# test444
# -m 指定输出的次数，这里只要第一个

# 找到 pkg-config 二进制所在的文件夹
DISTRO_PKG_CONFIG:=$(shell $(TOPDIR)/scripts/command_all.sh pkg-config | grep -e '/usr' -e '/nix/store' -m 1)

# 保存原始的PATH值
export ORIG_PATH:=$(if $(ORIG_PATH),$(ORIG_PATH),$(PATH))
# 将 OP自身的工具链加到PATH里面
export PATH:=$(if $(STAGING_DIR),$(abspath $(STAGING_DIR)/../host/bin),$(TOPDIR)/staging_dir/host/bin):$(PATH)

ifneq ($(OPENWRT_BUILD),1)
  # 清空make的 flag
  # MAKEFLAGS 是一个环境变量，它用于向 make 命令传递额外的标志和参数
  _SINGLE=export MAKEFLAGS=$(space);

  override OPENWRT_BUILD=1
  # 设置环境变量，使其可以跨脚本使用
  export OPENWRT_BUILD
  GREP_OPTIONS=
  export GREP_OPTIONS
  CDPATH=
  export CDPATH
  include $(TOPDIR)/include/debug.mk
  include $(TOPDIR)/include/depends.mk
  include $(TOPDIR)/include/toplevel.mk
else
  include rules.mk
  include $(INCLUDE_DIR)/depends.mk
  include $(INCLUDE_DIR)/subdir.mk
  include target/Makefile
  include package/Makefile
  include tools/Makefile
  include toolchain/Makefile

# Include the test suite Makefile if it exists
-include tests/Makefile

$(toolchain/stamp-compile): $(tools/stamp-compile) $(if $(CONFIG_BUILDBOT),toolchain_rebuild_check)
$(target/stamp-compile): $(toolchain/stamp-compile) $(tools/stamp-compile) $(BUILD_DIR)/.prepared
$(package/stamp-compile): $(target/stamp-compile) $(package/stamp-cleanup)
$(package/stamp-install): $(package/stamp-compile)
$(target/stamp-install): $(package/stamp-compile) $(package/stamp-install)
check: $(tools/stamp-check) $(toolchain/stamp-check) $(package/stamp-check)

printdb:
	# true 是 linux命令，什么都不做，默认成功退出
	# @ 用于不输出命令
	@true

prepare: $(target/stamp-compile)

_clean: FORCE
	rm -rf $(BUILD_DIR) $(STAGING_DIR) $(BIN_DIR) $(OUTPUT_DIR)/packages/$(ARCH_PACKAGES) $(TOPDIR)/staging_dir/packages

clean: _clean
	rm -rf $(BUILD_LOG_DIR)

targetclean: _clean
	rm -rf $(TOOLCHAIN_DIR) $(BUILD_DIR_BASE)/hostpkg $(BUILD_DIR_TOOLCHAIN)

dirclean: targetclean clean
	rm -rf $(STAGING_DIR_HOST) $(STAGING_DIR_HOSTPKG) $(BUILD_DIR_BASE)/host
	rm -rf $(TMP_DIR)
	$(MAKE) -C $(TOPDIR)/scripts/config clean

toolchain_rebuild_check:
	$(SCRIPT_DIR)/check-toolchain-clean.sh

cacheclean:
ifneq ($(CONFIG_CCACHE),)
	$(STAGING_DIR_HOST)/bin/ccache -C
endif

ifndef DUMP_TARGET_DB
$(BUILD_DIR)/.prepared: Makefile
	@mkdir -p $$(dirname $@)
	@touch $@

tmp/.prereq_packages: .config
	unset ERROR; \
	for package in $(sort $(prereq-y) $(prereq-m)); do \
		$(_SINGLE)$(NO_TRACE_MAKE) -s -r -C package/$$package prereq || ERROR=1; \
	done; \
	if [ -n "$$ERROR" ]; then \
		echo "Package prerequisite check failed."; \
		false; \
	fi
	touch $@
endif

# check prerequisites before starting to build
prereq: $(target/stamp-prereq) tmp/.prereq_packages
	@if [ ! -f "$(INCLUDE_DIR)/site/$(ARCH)" ]; then \
		echo 'ERROR: Missing site config for architecture "$(ARCH)" !'; \
		echo '       The missing file will cause configure scripts to fail during compilation.'; \
		echo '       Please provide a "$(INCLUDE_DIR)/site/$(ARCH)" file and restart the build.'; \
		exit 1; \
	fi

$(BIN_DIR)/profiles.json: FORCE
	$(if $(CONFIG_JSON_OVERVIEW_IMAGE_INFO), \
		WORK_DIR=$(BUILD_DIR)/json_info_files \
			$(SCRIPT_DIR)/json_overview_image_info.py $@ \
	)

json_overview_image_info: $(BIN_DIR)/profiles.json

checksum: FORCE
	$(call sha256sums,$(BIN_DIR),$(CONFIG_BUILDBOT))

buildversion: FORCE
	# 长这样，后面那部分应该来自最新的 commitid(f9f2dd1d93082d216135b6da891945d0331787d6)
	# r27797-f9f2dd1d93
	$(SCRIPT_DIR)/getver.sh > $(BIN_DIR)/version.buildinfo

feedsversion: FORCE
	# 长这样
	# src-git packages https://git.openwrt.org/feed/packages.git^30f383c8a8c89858c3f0a876619a51580f0b1e59
	# src-git luci https://git.openwrt.org/project/luci.git^e34c268411b2fea71e419be5dc0f8f6976d4e714
	# src-git routing https://git.openwrt.org/feed/routing.git^0ff4ab0506f2ab09b829699bef6b8be8bf8f87f1
	# src-git telephony https://git.openwrt.org/feed/telephony.git^7f4fa9e79193c1853e1761a68dca585849cff435
	$(SCRIPT_DIR)/feeds list -fs > $(BIN_DIR)/feeds.buildinfo

diffconfig: FORCE
	mkdir -p $(BIN_DIR)
	# 长这样
	# CONFIG_TARGET_x86=y
	# CONFIG_TARGET_x86_64=y
	# CONFIG_TARGET_x86_64_DEVICE_generic=y
	# CONFIG_IMAGEOPT=y
	# CONFIG_ISO_IMAGES=y
	# CONFIG_PACKAGE_cgi-io=y
	# CONFIG_PACKAGE_libiwinfo=y
	# CONFIG_PACKAGE_libiwinfo-data=y
	# CONFIG_PACKAGE_liblucihttp=y
	# CONFIG_PACKAGE_liblucihttp-ucode=y
	# CONFIG_PACKAGE_luci=y
	# CONFIG_PACKAGE_luci-app-firewall=y
	# CONFIG_PACKAGE_luci-base=y
	# CONFIG_PACKAGE_luci-light=y
	# CONFIG_PACKAGE_luci-mod-admin-full=y
	# CONFIG_PACKAGE_luci-mod-network=y
	# CONFIG_PACKAGE_luci-mod-status=y
	# CONFIG_PACKAGE_luci-mod-system=y
	# CONFIG_PACKAGE_luci-proto-ipv6=y
	# CONFIG_PACKAGE_luci-proto-ppp=y
	# CONFIG_PACKAGE_luci-theme-bootstrap=y
	# CONFIG_PACKAGE_rpcd=y
	# CONFIG_PACKAGE_rpcd-mod-file=y
	# CONFIG_PACKAGE_rpcd-mod-iwinfo=y
	# CONFIG_PACKAGE_rpcd-mod-luci=y
	# CONFIG_PACKAGE_rpcd-mod-rrdns=y
	# CONFIG_PACKAGE_rpcd-mod-ucode=y
	# CONFIG_PACKAGE_ucode-mod-html=y
	# CONFIG_PACKAGE_ucode-mod-math=y
	# CONFIG_PACKAGE_uhttpd=y
	# CONFIG_PACKAGE_uhttpd-mod-ubus=y
	# # CONFIG_PER_FEED_REPO is not set
	# CONFIG_TARGET_INITRAMFS_COMPRESSION_NONE=y
	# CONFIG_TARGET_ROOTFS_INITRAMFS=y
	$(SCRIPT_DIR)/diffconfig.sh > $(BIN_DIR)/config.buildinfo

buildinfo: FORCE
	$(_SINGLE)$(SUBMAKE) -r diffconfig buildversion feedsversion

prepare: .config $(tools/stamp-compile) $(toolchain/stamp-compile)
	$(_SINGLE)$(SUBMAKE) -r buildinfo

world: prepare $(target/stamp-compile) $(package/stamp-compile) $(package/stamp-install) $(target/stamp-install) FORCE
	# 定义在 openwrt/package/Makefile 里面
	$(_SINGLE)$(SUBMAKE) -r package/index
	$(_SINGLE)$(SUBMAKE) -r json_overview_image_info
	$(_SINGLE)$(SUBMAKE) -r checksum
ifneq ($(CONFIG_CCACHE),)
	$(STAGING_DIR_HOST)/bin/ccache -s
endif

.PHONY: clean dirclean prereq prepare world package/symlinks package/symlinks-install package/symlinks-clean

endif
