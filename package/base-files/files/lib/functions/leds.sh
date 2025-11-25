# Copyright (C) 2013 OpenWrt.org

# 通过设备树(Device Tree)获取LED控制路径
# $1：LED的别名（例如 power、wan、status 等）
# 输出：该LED在设备树中的完整路径，eg：/proc/device-tree/leds/led-1
get_dt_led_path() {
	# 存储最终路径
	local ledpath
	# 设备树基础路径
	local basepath="/proc/device-tree"
	# 设备树别名路径
	local nodepath="$basepath/aliases/led-$1"

	# 检查别名文件是否存在，并读取实际路径
	[ -f "$nodepath" ] && ledpath=$(cat "$nodepath")
	# 拼接完整路径（如果获取到非空值）
	[ -n "$ledpath" ] && ledpath="$basepath$ledpath"

	echo "$ledpath"
}

get_dt_led_color_func() {
	local enum
	local func
	local idx
	local label

	[ -e "$1/function" ] && func=$(cat "$1/function")
	[ -e "$1/color" ] && idx=$((0x$(hexdump -n 4 -e '4/1 "%02x"' "$1/color")))
	[ -e "$1/function-enumerator" ] && \
		enum=$((0x$(hexdump -n 4 -e '4/1 "%02x"' "$1/function-enumerator")))

	[ -z "$idx" ] && [ -z "$func" ] && return 2

	if [ -n "$idx" ]; then
		for color in "white" "red" "green" "blue" "amber" \
			     "violet" "yellow" "ir" "multicolor" "rgb" \
			     "purple" "orange" "pink" "cyan" "lime"
		do
			[ $idx -eq 0 ] && label="$color" && break
			idx=$((idx-1))
		done
	fi

	label="$label:$func"
	[ -n "$enum" ] && label="$label-$enum"
	echo "$label"

	return 0
}

# 从设备树(Device Tree)中提取LED标识名字
get_dt_led() {
	local label
	local ledpath=$(get_dt_led_path $1)

	# -n 变量非空
	# 读取到LED节点路径
	[ -n "$ledpath" ] && \
		# 标准LED标识
		label=$(cat "$ledpath/label" 2>/dev/null) || \
		# 无线信道专用标识
		label=$(cat "$ledpath/chan-name" 2>/dev/null) || \
		# 通过GPIO颜色推断
		label=$(get_dt_led_color_func "$ledpath") || \
		label=$(basename "$ledpath")

	echo "$label"
}

# 设置LED属性
# $1：LED设备名称
# $2：LED属性名称
# $3：要设置的属性值

# /sys/class/leds/
# ├── power/                   # LED设备目录
# │   ├── brightness           # 亮度控制 (0-255)，0 - 熄灭，128 - 半亮，255 - 全亮
# │   ├── max_brightness       # 最大亮度 (只读)
# │   ├── trigger              # 触发器类型，none - 手动控制，timer - 定时闪烁，heartbeat - 心跳模式，netdev - 网络活动（会配合 device_name、mode 等属性），phy0tx - 跟随数据发送，phy0rx - 跟随数据接收，oneshot - 单次闪烁
# │   ├── delay_on             # 开启延时 (ms)，trigger 为 timer 模式下，亮多久
# │   ├── delay_off            # 关闭延时 (ms)，trigger 为 timer 模式下，灭多久
# │   └── uevent               # 设备事件
# ├── status:green/            # 绿色状态LED
# ├── status:red/              # 红色状态LED
# ├── wlan/                    # WiFi指示LED
# └── lan1/                    # 网口1指示LED
led_set_attr() {
	# -f：检查LED属性文件是否存在
	# 将值写入LED属性文件
	[ -f "/sys/class/leds/$1/$2" ] && echo "$3" > "/sys/class/leds/$1/$2"
}

# 设置 LED 的定时模式
led_timer() {
	led_set_attr $1 "trigger" "timer"
	led_set_attr $1 "delay_on" "$2"
	led_set_attr $1 "delay_off" "$3"
}

# 用于开启 LED
# $1：LED设备名称（如 "power", "status", "wlan" 等）
led_on() {
	# 切换为手动控制，禁用自动触发器
	led_set_attr $1 "trigger" "none"
	# 将亮度设置为最亮
	led_set_attr $1 "brightness" 255
}

# 用于关闭 LED
# $1：LED设备名称（如 "power", "status", "wlan" 等）
led_off() {
	# 切换为手动控制，禁用自动触发器
	led_set_attr $1 "trigger" "none"
	# 将亮度设置为0
	led_set_attr $1 "brightness" 0
}

# 恢复LED默认触发器
# $1：LED标识符（通常是设备树中定义的LED别名）
status_led_restore_trigger() {
	local trigger
	# 获取的 LED 设备树路径
	local ledpath=$(get_dt_led_path $1)

	# [ -n "$ledpath" ]：检查LED路径是否非空
	[ -n "$ledpath" ] && \
		# 读取设备树中的默认触发器
		# 2>/dev/null：如果文件不存在，不输出错误
		trigger=$(cat "$ledpath/linux,default-trigger" 2>/dev/null)

	# 设置 LED 触发器为默认模式
	[ -n "$trigger" ] && \
		led_set_attr "$(get_dt_led $1)" "trigger" "$trigger"
}

status_led_set_timer() {
	led_timer $status_led "$1" "$2"
	[ -n "$status_led2" ] && led_timer $status_led2 "$1" "$2"
}

status_led_set_heartbeat() {
	led_set_attr $status_led "trigger" "heartbeat"
}

status_led_on() {
	led_on $status_led
	[ -n "$status_led2" ] && led_on $status_led2
}

status_led_off() {
	# 关闭 LED
	led_off $status_led
	# 如果存在 第二个状态灯，也关闭掉
	[ -n "$status_led2" ] && led_off $status_led2
}

status_led_blink_slow() {
	led_timer $status_led 1000 1000
}

status_led_blink_fast() {
	led_timer $status_led 100 100
}

# 设置为 preinit 的闪烁状态
status_led_blink_preinit() {
	led_timer $status_led 100 100
}

status_led_blink_failsafe() {
	led_timer $status_led 50 50
}

# 设置 LED 为闪烁模式
status_led_blink_preinit_regular() {
	led_timer $status_led 200 200
}
