#!/usr/bin/env perl
# 
# Copyright (C) 2006 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

use strict;

# 接受两个参数：$path（目录路径）和 $options（查找选项）
# 使用 find 命令查找 $path 下的所有文件，排除 .svn 和 CVS 目录
# 返回最新修改时间的文件及其时间戳
sub get_ts($$) {
	my $path = shift;
	my $options = shift;
	my $ts = 0;
	my $fn = "";
	$path .= "/" if( -d $path);
	open FIND, "find $path -type f -and -not -path \\*/.svn\\* -and -not -path \\*CVS\\* $options 2>/dev/null |";
	while (<FIND>) {
		chomp;
		my $file = $_;
		next if -l $file;
		my $mt = (stat $file)[9];
		if ($mt > $ts) {
			$ts = $mt;
			$fn = $file;
		}
	}
	close FIND;
	return ($ts, $fn);
}

# @ARGV 存储参数列表
(@ARGV > 0) or push @ARGV, ".";
my $ts = 0;
my $n = ".";
my %options;
while (@ARGV > 0) {
	my $path = shift @ARGV;
	# =~ 是 Perl 中的匹配操作符，用于将变量与正则表达式进行匹配
	# 以 -x 开头，-x 约定为占位符，需要转换为 find 参数 -and -not -path
	if ($path =~ /^-x/) {
		my $str = shift @ARGV;
		$options{"findopts"} .= " -and -not -path '".$str."'"
	} elsif ($path =~ /^-f/) {
		$options{"findopts"} .= " -follow";
	} elsif ($path =~ /^-n/) {
		my $arg = $ARGV[0];
		$options{$path} = $arg;
	} elsif ($path =~ /^-/) {
		$options{$path} = 1;
	} else {
		my ($tmp, $fname) = get_ts($path, $options{"findopts"});
		if ($tmp > $ts) {
			if ($options{'-F'}) {
				$n = $fname;
			} else {
				$n = $path;
			}
			$ts = $tmp;
		}
	}
}

# 通过 -n 指定了对比文件，则使用退出码指示结果
if ($options{"-n"}) {
	# 如果得到的文件夹中的最新文件 跟 对比文件（通过-n指定）一样，则返回0
	exit ($n eq $options{"-n"} ? 0 : 1);
} elsif ($options{"-p"}) {
	# 输出对应结果，默认输出完整路径，可以通过 -F 输出文件名
	print "$n\n";
} elsif ($options{"-t"}) {
	# 输出最新文件的时间戳
	print "$ts\n";
} else {
	print "$n\t$ts\n";
}
