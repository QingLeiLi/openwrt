#!/bin/sh
# 没找到 scripts/config/conf 的目标定义，应该是用隐含规则直接编译这个c文件
make ./scripts/config/conf >/dev/null || { make ./scripts/config/conf; exit 1; }
# 在 .config 搜索
# head -n3 是提取前三行
grep \^CONFIG_TARGET_ .config | head -n3 > tmp/.diffconfig.head
grep \^CONFIG_TARGET_DEVICE_ .config >> tmp/.diffconfig.head
grep '^CONFIG_ALL=y' .config >> tmp/.diffconfig.head
grep '^CONFIG_ALL_KMODS=y' .config >> tmp/.diffconfig.head
grep '^CONFIG_ALL_NONSHARED=y' .config >> tmp/.diffconfig.head
grep '^CONFIG_DEVEL=y' .config >> tmp/.diffconfig.head
grep '^CONFIG_TOOLCHAINOPTS=y' .config >> tmp/.diffconfig.head
grep '^CONFIG_BUSYBOX_CUSTOM=y' .config >> tmp/.diffconfig.head
grep '^CONFIG_TARGET_PER_DEVICE_ROOTFS=y' .config >> tmp/.diffconfig.head
# -w 是指定输出的文件
./scripts/config/conf --defconfig=tmp/.diffconfig.head -w tmp/.diffconfig.stage1 Config.in >/dev/null
# >+ 是脚本的参数，用于标识返回diff
./scripts/kconfig.pl '>+' tmp/.diffconfig.stage1 .config >> tmp/.diffconfig.head
./scripts/config/conf --defconfig=tmp/.diffconfig.head -w tmp/.diffconfig.stage2 Config.in >/dev/null
./scripts/kconfig.pl '>' tmp/.diffconfig.stage2 .config >> tmp/.diffconfig.head
cat tmp/.diffconfig.head
rm -f tmp/.diffconfig tmp/.diffconfig.head
