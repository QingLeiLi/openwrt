# 定义分割符为 /，每行会被拆分为多个字段
BEGIN { FS="/" }
# $NF 表示行切割后最后一个字段
# $0 表示整行
# 以 feeds 开头的行，将最后一个字段作为索引，整行作为值存入 FEEDS 数组
$1 ~ /^feeds/ { FEEDS[$NF]=$0 }
# 不以 feeds 开头的行，将最后一个字段作为索引，整行作为值存入 PKGS 数组
$1 !~ /^feeds/ { PKGS[$NF]=$0 }
END {
	# Filter-out OpenWrt packages which have a feeds equivalent
	for (pkg in PKGS)
		if (pkg in FEEDS) {
			print PKGS[pkg] > of
			delete PKGS[pkg]
		}
	n = asort(PKGS)
	for (i=1; i <= n; i++) {
		print PKGS[i]
	}
	n = asort(FEEDS)
	for (i=1; i <= n; i++){
		print FEEDS[i]
	}
}
