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

set_led_state() {
	status_led="$boot"

	case "$1" in
	preinit)
		status_led_blink_preinit
		;;
	failsafe)
		status_led_off
		[ -n "$running" ] && {
			status_led="$running"
			status_led_off
		}
		status_led="$failsafe"
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
			status_led_restore_trigger "boot"
		[ -n "$running" ] && {
			status_led="$running"
			status_led_on
		}
		;;
	esac
}

# $1 表示目标状态（如 failsafe、upgrade 等）
set_state() {
	# -o：表示逻辑"OR"（任一条件为真即执行）
	[ -n "$boot" -o -n "$failsafe" -o -n "$running" -o -n "$upgrade" ] && set_led_state "$1"
}
