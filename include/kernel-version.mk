
# Use the default kernel version if the Makefile doesn't override it
LINUX_RELEASE?=1

ifdef CONFIG_TESTING_KERNEL
  KERNEL_PATCHVER:=$(KERNEL_TESTING_PATCHVER)
endif

KERNEL_DETAILS_FILE=$(GENERIC_PLATFORM_DIR)/kernel-$(KERNEL_PATCHVER)
ifeq ($(wildcard $(KERNEL_DETAILS_FILE)),)
  $(error Missing kernel version/hash file for $(KERNEL_PATCHVER). Please create $(KERNEL_DETAILS_FILE))
endif

include $(KERNEL_DETAILS_FILE)

ifdef KERNEL_TESTING_PATCHVER
  KERNEL_TESTING_DETAILS_FILE=$(GENERIC_PLATFORM_DIR)/kernel-$(KERNEL_TESTING_PATCHVER)
  ifeq ($(wildcard $(KERNEL_TESTING_DETAILS_FILE)),)
    $(error Missing kernel version/hash file for $(KERNEL_TESTING_PATCHVER). Please create $(KERNEL_TESTING_DETAILS_FILE))
  endif

  include $(KERNEL_TESTING_DETAILS_FILE)
endif

# 移除前缀
remove_uri_prefix=$(subst git://,,$(subst http://,,$(subst https://,,$(1))))
# 将 @ : . - / 替换为 _
sanitize_uri=$(call qstrip,$(subst @,_,$(subst :,_,$(subst .,_,$(subst -,_,$(subst /,_,$(1)))))))

ifneq ($(call qstrip,$(CONFIG_KERNEL_GIT_CLONE_URI)),)
  LINUX_VERSION:=$(call sanitize_uri,$(call remove_uri_prefix,$(CONFIG_KERNEL_GIT_CLONE_URI)))
  ifeq ($(call qstrip,$(CONFIG_KERNEL_GIT_REF)),)
    CONFIG_KERNEL_GIT_REF:=HEAD
  endif
  LINUX_VERSION:=$(LINUX_VERSION)-$(call sanitize_uri,$(CONFIG_KERNEL_GIT_REF))
else
ifdef KERNEL_PATCHVER
  LINUX_VERSION:=$(KERNEL_PATCHVER)$(strip $(LINUX_VERSION-$(KERNEL_PATCHVER)))
endif
ifdef KERNEL_TESTING_PATCHVER
  LINUX_TESTING_VERSION:=$(KERNEL_TESTING_PATCHVER)$(strip $(LINUX_VERSION-$(KERNEL_TESTING_PATCHVER)))
endif
endif

# 将版本号的 . 替换为 空格
split_version=$(subst ., ,$(1))
# split_version 的反向操作
merge_version=$(subst $(space),.,$(1))
KERNEL_BASE=$(firstword $(subst -, ,$(LINUX_VERSION)))
# $(wordlist start, end, text)：返回 text 中的第 start 到 end 个单词
KERNEL=$(call merge_version,$(wordlist 1,2,$(call split_version,$(KERNEL_BASE))))
KERNEL_PATCHVER ?= $(KERNEL)

# 内核的hash，从 KERNEL_DETAILS_FILE 中定义的
# disable the md5sum check for unknown kernel versions
LINUX_KERNEL_HASH:=$(LINUX_KERNEL_HASH-$(strip $(LINUX_VERSION)))
LINUX_KERNEL_HASH?=x
