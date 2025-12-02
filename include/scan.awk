# 区分 OpenWrt 核心包和 feeds 包，并处理重复项
# feeds 开头的都是从三方仓库拉取的
# 不以 feeds 开头的都是 OpenWrt 核心包

# 定义分割符为 /，每行会被拆分为多个字段
BEGIN { FS="/" }
# $NF 表示行切割后最后一个字段
# $0 表示整行
# 以 feeds 开头的行，将最后一个字段作为索引，整行作为值存入 FEEDS 数组
# feeds/packages/net/curl → FEEDS["curl"] = "feeds/packages/net/curl"
$1 ~ /^feeds/ { FEEDS[$NF]=$0 }
# 不以 feeds 开头的行，将最后一个字段作为索引，整行作为值存入 PKGS 数组
# package/kernel/linux会被处理为 PKGS["linux"] = "package/kernel/linux"
$1 !~ /^feeds/ { PKGS[$NF]=$0 }
END {
	# Filter-out OpenWrt packages which have a feeds equivalent
	for (pkg in PKGS)
		# 处理重复包：如果核心包和 feeds 包同名，优先选择核心包
		if (pkg in FEEDS) {
			# 将重名的核心包输出到 of 文件
			print PKGS[pkg] > of
			delete PKGS[pkg]
		}
	# 按字母顺序排序剩余的核心包
	n = asort(PKGS)
	for (i=1; i <= n; i++) {
		# 这个只是打印，并没有输出到 of 文件
		print PKGS[i]
	}
	n = asort(FEEDS)
	for (i=1; i <= n; i++){
		print FEEDS[i]
	}
}
