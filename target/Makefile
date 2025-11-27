# 
# Copyright (C) 2007 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#
curdir:=target

# 会被 subdir 使用
$(curdir)/subtargets:=install
# 会被 subdir 使用
$(curdir)/builddirs:=linux sdk imagebuilder toolchain llvm-bpf
# 目标默认的子目录，优先级比 builddirs 高
$(curdir)/builddirs-default:=linux
# 为 install 目标指定的子目录，优先级比 builddirs-default 高
$(curdir)/builddirs-install:=\
	linux \
	$(if $(CONFIG_SDK),sdk) \
	$(if $(CONFIG_IB),imagebuilder) \
	$(if $(CONFIG_MAKE_TOOLCHAIN),toolchain) \
	$(if $(CONFIG_SDK_LLVM_BPF),llvm-bpf)

$(curdir)/sdk/install:=$(curdir)/linux/install
$(curdir)/imagebuilder/install:=$(curdir)/linux/install

$(curdir)//compile = $(STAGING_DIR)/.prepared $(BIN_DIR)

# 构建 $$(target/stamp-prereq) 目标
# 真正的目标名是：$(STAGING_DIR))/stamp/.target_prereq
$(eval $(call stampfile,$(curdir),target,prereq,.config))
# 构建 $$(target/stamp-compile) 目标
# 真正的目标名是：$(STAGING_DIR))/stamp/.target_compile
$(eval $(call stampfile,$(curdir),target,compile,$(TMP_DIR)/.build))
# 构建 $$(target/stamp-install) 目标
# 真正的目标名是：$(STAGING_DIR))/stamp/.target_install
$(eval $(call stampfile,$(curdir),target,install,$(TMP_DIR)/.build))

$($(curdir)/stamp-install): $($(curdir)/stamp-compile)

$(eval $(call subdir,$(curdir)))
