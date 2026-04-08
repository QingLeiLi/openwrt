# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2006-2020 OpenWrt.org

# 根据包源文件的扩展名自动选择解压/解包命令，并把内容展开到构建目录的上一级目录。

HOST_TAR:=$(TAR)
TAR_CMD=$(HOST_TAR) -C $(1)/.. $(TAR_OPTIONS)
UNZIP_CMD=unzip -q -d $(1)/.. $(DL_DIR)/$(PKG_SOURCE)

# 没有包路径的时候，默认无需解压
ifeq ($(PKG_SOURCE),)
  PKG_UNPACK ?= true
else

# UNPACK_CMD 如果为空
ifeq ($(strip $(UNPACK_CMD)),)
  ifeq ($(strip $(PKG_CAT)),)
    # try to autodetect file type
    EXT:=$(call ext,$(PKG_SOURCE))
    EXT1:=$(EXT)

    ifeq ($(filter gz tgz,$(EXT)),$(EXT))
      EXT:=$(call ext,$(PKG_SOURCE:.$(EXT)=))
      DECOMPRESS_CMD:=$(STAGING_DIR_HOST)/bin/libdeflate-gzip -dc $(DL_DIR)/$(PKG_SOURCE) |
    endif
    ifeq ($(filter bzip2 bz2 bz tbz2 tbz,$(EXT)),$(EXT))
      EXT:=$(call ext,$(PKG_SOURCE:.$(EXT)=))
      DECOMPRESS_CMD:=bzcat $(DL_DIR)/$(PKG_SOURCE) |
    endif
    ifeq ($(filter xz txz,$(EXT)),$(EXT))
      EXT:=$(call ext,$(PKG_SOURCE:.$(EXT)=))
      DECOMPRESS_CMD:=xzcat $(DL_DIR)/$(PKG_SOURCE) |
    endif
    ifeq (zst,$(EXT))
      EXT:=$(call ext,$(PKG_SOURCE:.$(EXT)=))
      DECOMPRESS_CMD:=zstdcat $(DL_DIR)/$(PKG_SOURCE) |
    endif
    ifeq ($(filter tgz tbz tbz2 txz,$(EXT1)),$(EXT1))
      EXT:=tar
    endif
    # DECOMPRESS 先识别外层压缩（gz/bz2/xz/zst），设置 DECOMPRESS_CMD（流式解压到 stdout）
    DECOMPRESS_CMD ?= cat $(DL_DIR)/$(PKG_SOURCE) |
    # 再识别内层归档（tar/cpio/zip），形成 UNPACK 命令
    ifeq ($(EXT),tar)
      UNPACK_CMD=$(DECOMPRESS_CMD) $(TAR_CMD)
    endif
    ifeq ($(EXT),cpio)
      UNPACK_CMD=$(DECOMPRESS_CMD) (cd $(1)/..; $(STAGING_DIR_HOST)/bin/cpio -i -d)
    endif
    ifeq ($(EXT),zip)
      UNPACK_CMD=$(UNZIP_CMD)
    endif
  endif

  # 兼容旧变量 PKG_CAT，上面的处理逻辑只有在 PKG_CAT 为空时才处理，如果设置了 PKG_CAT，UNPACK_CMD 为空
  # 如果历史包定义了 PKG_CAT（如 zcat/unzip），按其习惯构造管道；
  # compatibility code for packages that set PKG_CAT
  ifeq ($(strip $(UNPACK_CMD)),)
    # use existing PKG_CAT
    UNPACK_CMD=$(PKG_CAT) $(DL_DIR)/$(PKG_SOURCE) | $(TAR_CMD)
    ifeq ($(PKG_CAT),unzip)
      UNPACK_CMD=$(UNZIP_CMD)
    endif
    # zcat 会被替换为 STAGING 的 libdeflate-gzip 实现，规避不同系统 zcat 行为差异
    # replace zcat with $(ZCAT), because some system don't support it properly
    ifeq ($(PKG_CAT),zcat)
      UNPACK_CMD=$(STAGING_DIR_HOST)/bin/libdeflate-gzip -dc $(DL_DIR)/$(PKG_SOURCE) | $(TAR_CMD)
    endif
  endif
endif

# 生成可调用的宏
ifdef PKG_BUILD_DIR
  PKG_UNPACK ?= $(SH_FUNC) $(call UNPACK_CMD,$(PKG_BUILD_DIR))
endif
ifdef HOST_BUILD_DIR
  HOST_UNPACK ?= $(SH_FUNC) $(call UNPACK_CMD,$(HOST_BUILD_DIR))
endif

endif # PKG_SOURCE

