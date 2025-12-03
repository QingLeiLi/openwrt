# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2006-2020 OpenWrt.org

# 输出大概是这样子：
# Source-Makefile: feeds/luci/applications/luci-app-acl/Makefile
# Build-Depends: lua/host luci-base/host LUCI_CSSTIDY:csstidy/host LUCI_SRCDIET:luasrcdiet/host

# Package: luci-app-acl
# Submenu: 3. Applications
# Version: x
# Depends: +libc +luci-base
# Conflicts:
# Menu-Depends:
# Provides:
# Section: luci
# Category: LuCI
# Repository: base
# Title: LuCI account management module
# Maintainer: OpenWrt LuCI community
# Source:
# License: Apache-2.0
# URL: https://github.com/openwrt/luci
# Type: ipkg
# Description: LuCI account management module
# @@


ifneq ($(DUMP),)

# 输出文件级别信息
define SOURCE_INFO
$(if $(PKG_BUILD_DEPENDS),Build-Depends: $(PKG_BUILD_DEPENDS)
)$(if $(HOST_BUILD_DEPENDS),Build-Depends/host: $(HOST_BUILD_DEPENDS)
)$(if $(BUILD_TYPES),Build-Types: $(BUILD_TYPES)
)

endef

# 输出包级别信息
define Dumpinfo/Package
$(info $(SOURCE_INFO)Package: $(1)
$(if $(MENU),Menu: $(MENU)
)$(if $(SUBMENU),Submenu: $(SUBMENU)
)$(if $(SUBMENUDEP),Submenu-Depends: $(SUBMENUDEP)
)$(if $(DEFAULT),Default: $(DEFAULT)
)$(if $(findstring $(PREREQ_CHECK),1),Prereq-Check: 1
)Version: $(VERSION)
Depends: $(call PKG_FIXUP_DEPENDS,$(1),$(DEPENDS))
Conflicts: $(CONFLICTS)
Menu-Depends: $(MDEPENDS)
Provides: $(PROVIDES)
$(if $(VARIANT),Build-Variant: $(VARIANT)
$(if $(DEFAULT_VARIANT),Default-Variant: $(VARIANT)
))Section: $(SECTION)
Category: $(CATEGORY)
$(if $(filter nonshared,$(PKGFLAGS)),,Repository: $(if $(FEED),$(FEED),base)
)Title: $(TITLE)
Maintainer: $(MAINTAINER)
$(if $(USERID),Require-User: $(USERID)
)Source: $(PKG_SOURCE)
$(if $(LICENSE),License: $(LICENSE)
)$(if $(LICENSE_FILES),LicenseFiles: $(LICENSE_FILES)
)$(if $(PKG_CPE_ID),CPE-ID: $(PKG_CPE_ID)
)$(if $(URL),URL: $(URL)
)$(if $(ABI_VERSION),ABI-Version: $(ABI_VERSION)
)Type: $(if $(Package/$(1)/targets),$(Package/$(1)/targets),$(if $(PKG_TARGETS),$(PKG_TARGETS),ipkg))
$(if $(KCONFIG),Kernel-Config: $(KCONFIG)
)$(if $(BUILDONLY),Build-Only: $(BUILDONLY)
)$(if $(HIDDEN),Hidden: $(HIDDEN)
)Description: $(if $(Package/$(1)/description),$(Package/$(1)/description),$(TITLE))
@@
$(if $(Package/$(1)/config),Config:
$(Package/$(1)/config)
@@
))
SOURCE_INFO :=
endef

dumpinfo: FORCE
	# SOURCE_INFO 会被展开执行
	$(if $(SOURCE_INFO),$(info $(SOURCE_INFO)))

endif
