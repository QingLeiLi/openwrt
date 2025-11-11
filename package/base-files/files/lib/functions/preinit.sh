# Copyright (C) 2006-2013 OpenWrt.org
# Copyright (C) 2010 Vertical Communications

boot_hook_splice_start() {
	export -n PI_HOOK_SPLICE=1
}

boot_hook_splice_finish() {
	local hook
	for hook in $PI_STACK_LIST; do
		local v; eval "v=\${${hook}_splice:+\$${hook}_splice }$hook"
		export -n "${hook}=${v% }"
		export -n "${hook}_splice="
	done
	export -n PI_HOOK_SPLICE=
}

# 初始化 hook
boot_hook_init() {
	# 构造钩子变量名，preinit_hook
	local hook="${1}_hook"
	# Shell参数展开的条件替换语法，格式：${variable:+word}
	# 含义：如果variable非空，则返回word，否则返回空字符串
	# -n 选项表示"不导出"，即设置变量但不将其导出到子进程环境
	# PI_STACK_LIST 收集所有的 hook 名字，空格隔开
	export -n "PI_STACK_LIST=${PI_STACK_LIST:+$PI_STACK_LIST }$hook"
	# 定义钩子存储变量，初始为空
	export -n "$hook="
}

# 向特定 hook 添加 处理函数
boot_hook_add() {
	# 构造钩子名（支持splice）
	# 每个 hook 应该分为 xx_hook 和 xx_hook_splice 两个变量
	local hook="${1}_hook${PI_HOOK_SPLICE:+_splice}"
	# 要添加的处理函数名字
	local func="${2}"

	# 检查函数名非空
	[ -n "$func" ] && {
		# 获取当前钩子值
		# eval 最终执行的是：v = $xx_hook
		# 获取当前变量的值，存储到 v 中
		local v; eval "v=\$$hook"
		# 追加新的处理函数
		export -n "$hook=${v:+$v }$func"
	}
}

# 从钩子列表（hook）中弹出首个函数名
# 队列出队函数，从钩子函数列表中取出第一个函数
# 类似于数组的shift操作
boot_hook_shift() {
	# 构造完整的钩子变量名（如 "preinit_main_hook"）
	local hook="${1}_hook"
	# 接收结果的变量名（由调用者指定）
	local rvar="${2}"

	# 获取钩子列表的值（通过动态变量名访问）
	# 用于存储取出的函数的变量名

	# 得到 hook 变量的值
	local v; eval "v=\$$hook"
	# 如果列表非空
	[ -n "$v" ] && {
		# 提取第一个函数名（删除第一个空格后的所有内容）
		# ${v%% *} 表示从右边开始，删除最长匹配的 " *" 模式
		# "func1 func2 func3" → "func1"
		local first="${v%% *}"

		# 如果还有其他函数，更新 hook 变量，否则清空钩子列表
		# ${v#* } 表示从左边开始，删除最短匹配的 "* " 模式
		# "func1 func2 func3" → "func2 func3"
		# 如果原字符串和处理后的字符串不同，说明还有其他函数
		[ "$v" != "${v#* }" ] && \
			# 更新钩子变量为剩余列表
			export -n "$hook=${v#* }" || \
			# 否则清空钩子变量
			export -n "$hook="

		# 将第一个函数名存入调用者指定的变量
		# 将第一个函数名存储到返回变量
		export -n "$rvar=$first"
		return 0
	}

	# 列表为空时返回失败
	return 1
}

# 用于动态执行指定钩子（hook）中注册的所有函数
# 钩子执行引擎，负责依次执行钩子中的所有函数，并防止重复执行。
boot_run_hook() {
	# 钩子名称
	local hook="$1"
	# 用于存储当前要执行的函数
	local func

	while boot_hook_shift "$hook" func; do
		# 检查函数是否已执行，执行状态存储在 PI_RAN_xx 变量中
		local ran; eval "ran=\$PI_RAN_$func"
		[ -n "$ran" ] || {
			# 标记为已执行
			export -n "PI_RAN_$func=1"
			# 执行函数并传递参数，只支持2个参数？第一个还是 hook 名字
			$func "$1" "$2"
		}
	done
}

pivot() { # <new_root> <old_root>
	/bin/mount -o noatime,move /proc $1/proc && \
	pivot_root $1 $1$2 && {
		/bin/mount -o noatime,move $2/dev /dev
		/bin/mount -o noatime,move $2/tmp /tmp
		/bin/mount -o noatime,move $2/sys /sys 2>&-
		/bin/mount -o noatime,move $2/overlay /overlay 2>&-
		return 0
	}
}

fopivot() { # <rw_root> <work_dir> <ro_root> <dupe?>
	/bin/mount -o noatime,lowerdir=/,upperdir=$1,workdir=$2 -t overlay "overlayfs:$1" /mnt
	pivot /mnt $3
}

ramoverlay() {
	mkdir -p /tmp/root
	/bin/mount -t tmpfs -o noatime,mode=0755 root /tmp/root
	mkdir -p /tmp/root/root /tmp/root/work
	fopivot /tmp/root/root /tmp/root/work /rom 1
}
