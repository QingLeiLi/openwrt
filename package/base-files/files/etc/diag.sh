#!/bin/sh
# Copyright (C) 2006-2019 OpenWrt.org
# OpenWrt 的 LED 诊断状态脚本，只是定义了LED设置函数，等待调用
# 通常用于初始化路由器指示灯状态（例如：启动时设为黄色闪烁，启动完成切绿色）

. /lib/functions/leds.sh

# 尝试匹配到 boot 的led设备树名字
boot="$(get_dt_led boot)"
failsafe="$(get_dt_led failsafe)"
running="$(get_dt_led running)"
upgrade="$(get_dt_led upgrade)"

# 设置 LED 指示状态
set_led_state() {
	status_led="$boot"

	case "$1" in
	preinit)
		status_led_blink_preinit
		;;
	failsafe)
		# 关闭 boot 提示灯
		# 他会关闭 status_led 指向的 LED
		status_led_off
		[ -n "$running" ] && {
			status_led="$running"
			# 关闭 running 提示灯
			status_led_off
		}
		status_led="$failsafe"
		# 设置 failsafe LED 为闪烁模式
		status_led_blink_failsafe
		;;
	preinit_regular)
		status_led_blink_preinit_regular
		;;
	upgrade)
		[ -n "$running" ] && {
			status_led="$running"
			status_led_off
		}
		status_led="$upgrade"
		status_led_blink_preinit_regular
		;;
	done)
		status_led_off
		[ "$status_led" != "$running" ] && \
			# 恢复 boot 指示灯的 trigger 为默认模式
			status_led_restore_trigger "boot"
		# 打开运行状态灯
		[ -n "$running" ] && {
			status_led="$running"
			status_led_on
		}
		;;
	esac
}

# $1 表示目标状态（如 failsafe、upgrade 等）
# set_state failsafe
set_state() {
	# -n 测试变量是否非空，如果变量有内容（长度大于0），返回真
	# -o：表示逻辑"OR"（任一条件为真即执行）
	# 至少获取到一个设备树节点，才会执行
	[ -n "$boot" -o -n "$failsafe" -o -n "$running" -o -n "$upgrade" ] && set_led_state "$1"
}
