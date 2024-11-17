#! /bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Reduced version of which -a using command utility

case $PATH in
        # 如果路径不是以:结尾，就加上:
	(*[!:]:) PATH="$PATH:" ;;
esac

# 将 path中的 : 替换为 \n，开始遍历每行
for ELEMENT in $(echo $PATH | tr ":" "\n"); do
        # $@ 是脚本得到的所有参数，透传过来的外面是通过 `command_all.sh pkg-config` 调用的，就代表 pkg-config 参数
        # command -v 是查找命令的路径，如果找到就输出路径，找不到就返回1
        # ➜  openwrt git:(main) ✗ command -v ps
        # /bin/ps
        # 将PATH临时替换为只有一条路径，所以 查找的命令就仅限在当前路径下了
        # 以此来判断二进制命令在哪些 PATH的路径下有
        PATH=$ELEMENT command -v "$@"
done
