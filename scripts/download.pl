#!/usr/bin/env perl
# 
# Copyright (C) 2006 OpenWrt.org
# Copyright (C) 2016 LEDE project
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

use strict;
use warnings;
use File::Basename;
use File::Copy;
use File::Path;
use Text::ParseWords;
use JSON::PP;

@ARGV > 2 or die "Syntax: $0 <target dir> <filename> <hash> <url filename> [<mirror> ...]\n";

my $url_filename;
# DownloadDir
my $target = glob(shift @ARGV);
# DownloadFileName
my $filename = shift @ARGV;
# FileHash
my $file_hash = shift @ARGV;
$url_filename = shift @ARGV unless $ARGV[0] =~ /:\/\//;
my $scriptdir = dirname($0);
my @mirrors;
my $ok;

my $check_certificate = $ENV{DOWNLOAD_CHECK_CERTIFICATE} eq "y";
my $custom_tool = $ENV{DOWNLOAD_TOOL_CUSTOM};
my $download_tool;

$url_filename or $url_filename = $filename;

# 从多处获取镜像地址
sub localmirrors {
	my @mlist;
	# 从 scripts 目录下读取 localmirrors 作为镜像
	open LM, "$scriptdir/localmirrors" and do {
	    while (<LM>) {
			chomp $_;
			push @mlist, $_ if $_;
		}
		close LM;
	};
	# 在 .config 文件中匹配 CONFIG_LOCALMIRROR 作为镜像地址
	# < 表示只读模式打开
	open CONFIG, "<".$ENV{'TOPDIR'}."/.config" and do {
		while (<CONFIG>) {
			/^CONFIG_LOCALMIRROR="(.+)"/ and do {
				chomp;
				my @local_mirrors = split(/;/, $1);
				push @mlist, @local_mirrors;
			};
		}
		close CONFIG;
	};

	# 从环境变量读取镜像
	my $mirror = $ENV{'DOWNLOAD_MIRROR'};
	$mirror and push @mlist, split(/;/, $mirror);

	return @mlist;
}

# 获取现有项目的镜像
sub projectsmirrors {
	my $project = shift;
	my $append = shift;

	# 长这样
	# {
	# 	"@SF": [
	# 		"https://downloads.sourceforge.net"
	# 	],
	# }
	open (PM, "$scriptdir/projectsmirrors.json") ||
		die "Can´t open $scriptdir/projectsmirrors.json: $!\n";
	# 将输入记录分隔符 $/ 设置为未定义值，使得 <PM> 读取整个文件内容，而不是逐行读取
	local $/;
	# 读取文件句柄 PM 中的所有内容
	my $mirror_json = <PM>;
	my $mirror = decode_json $mirror_json;

	foreach (@{$mirror->{$project}}) {
		# $_：当前循环中的元素
		# 向 @mirrors push 一个元素，@mirrors.push(`${$_}/${append || ''}`)
		push @mirrors, $_ . "/" . ($append or "");
	}
}

sub which($) {
	my $prog = shift;
	my $res = `command -v $prog`;
	$res or return undef;
	return $res;
}

sub hash_cmd() {
	my $len = length($file_hash);
	my $cmd;

	$len == 64 and return "$ENV{'MKHASH'} sha256";
	$len == 32 and return "$ENV{'MKHASH'} md5";
	return undef;
}

# 检查下载工具是否存在
sub tool_present {
	my $tool_name = shift;
	my $compare_line = shift;
	my $present = 0;

	# 运行命令行，忽略错误输出，将标准输出重定向到 TOOL（命令结尾有管道符）
	if (open TOOL, "$tool_name --version 2>/dev/null |") {
		# 如果正常读到了一行内容
		if (defined(my $line = readline TOOL)) {
			# 如果输出以 $compare_line 开头，则认为工具存在
			$present = 1 if $line =~ /^$compare_line /;
		}
		close TOOL;
	}

	return $present
}

# 通过能力检测选择下载工具
sub select_tool {
	# 删除双引号
	$custom_tool =~ tr/"//d;
	if ($custom_tool) {
		return $custom_tool;
	}

	# Try to use curl if available
	# 执行 `curl --version`，然后判断第一行输出是否以 `curl` 开头
	# 正常输出是
	# curl 8.6.0 (x86_64-apple-darwin23.0) libcurl/8.6.0 (SecureTransport) LibreSSL/3.3.6 zlib/1.2.12 nghttp2/1.61.0
	if (tool_present("curl", "curl")) {
		return "curl";
	}

	# No tool found, fallback to wget
	return "wget";
}

sub download_cmd {
	my $url = shift;
	my $filename = shift;

	if ($download_tool eq "curl") {
		return (qw(curl -f --connect-timeout 20 --retry 5 --location),
			$check_certificate ? () : '--insecure',
			shellwords($ENV{CURL_OPTIONS} || ''),
			$url);
	} elsif ($download_tool eq "wget") {
		return (qw(wget --tries=5 --timeout=20 --output-document=-),
			$check_certificate ? () : '--no-check-certificate',
			shellwords($ENV{WGET_OPTIONS} || ''),
			$url);
	} elsif ($download_tool eq "aria2c") {
		my $additional_mirrors = join(" ", map "$_/$filename", @_);
		my @chArray = ('a'..'z', 'A'..'Z', 0..9);
		my $rfn = join '', "${filename}_", map{ $chArray[int rand @chArray] } 0..9;

		@mirrors=();

		return join(" ", "[ -d $ENV{'TMPDIR'}/aria2c ] || mkdir $ENV{'TMPDIR'}/aria2c;",
			"touch $ENV{'TMPDIR'}/aria2c/${rfn}_spp;",
			qw(aria2c --stderr -c -x2 -s10 -j10 -k1M), $url, $additional_mirrors,
			$check_certificate ? () : '--check-certificate=false',
			"--server-stat-of=$ENV{'TMPDIR'}/aria2c/${rfn}_spp",
			"--server-stat-if=$ENV{'TMPDIR'}/aria2c/${rfn}_spp",
			"--daemon=false --no-conf", shellwords($ENV{ARIA2C_OPTIONS} || ''),
			"-d $ENV{'TMPDIR'}/aria2c -o $rfn;",
			"cat $ENV{'TMPDIR'}/aria2c/$rfn;",
			"rm $ENV{'TMPDIR'}/aria2c/$rfn $ENV{'TMPDIR'}/aria2c/${rfn}_spp");
	} else {
		return join(" ", $download_tool, $url);
	}
}

my $hash_cmd = hash_cmd();
$hash_cmd or ($file_hash eq "skip") or die "Cannot find appropriate hash command, ensure the provided hash is either a MD5 or SHA256 checksum.\n";

sub download
{
	my $mirror = shift;
	my $download_filename = shift;
	# 获取剩余所有的参数
	my @additional_mirrors = @_;

	# 去掉镜像末尾的 /
	$mirror =~ s!/$!!;

	# 如果镜像以 file:// 开头，表示本地镜像
	if ($mirror =~ s!^file://!!) {
		if (! -d "$mirror") {
			print STDERR "Wrong local cache directory -$mirror-.\n";
			cleanup();
			return;
		}

		if (! -d "$target") {
			make_path($target);
		}

		if (! open TMPDLS, "find $mirror -follow -name $filename 2>/dev/null |") {
			print("Failed to search for $filename in $mirror\n");
			return;
		}

		my $link;

		while (defined(my $line = readline TMPDLS)) {
			chomp ($link = $line);
			if ($. > 1) {
				print("$. or more instances of $filename in $mirror found . Only one instance allowed.\n");
				return;
			}
		}

		close TMPDLS;

		if (! $link) {
			print("No instances of $filename found in $mirror.\n");
			return;
		}

		print("Copying $filename from $link\n");
		copy($link, "$target/$filename.dl");

		$hash_cmd and do {
			if (system("cat '$target/$filename.dl' | $hash_cmd > '$target/$filename.hash'")) {
				print("Failed to generate hash for $filename\n");
				return;
			}
		};
	} else {
		my @cmd = download_cmd("$mirror/$download_filename", $download_filename, @additional_mirrors);
		print STDERR "+ ".join(" ",@cmd)."\n";
		open(FETCH_FD, '-|', @cmd) or die "Cannot launch aria2c, curl or wget.\n";
		$hash_cmd and do {
			open MD5SUM, "| $hash_cmd > '$target/$filename.hash'" or die "Cannot launch $hash_cmd.\n";
		};
		open OUTPUT, "> $target/$filename.dl" or die "Cannot create file $target/$filename.dl: $!\n";
		my $buffer;
		while (read FETCH_FD, $buffer, 1048576) {
			$hash_cmd and print MD5SUM $buffer;
			print OUTPUT $buffer;
		}
		$hash_cmd and close MD5SUM;
		close FETCH_FD;
		close OUTPUT;

		if ($? >> 8) {
			print STDERR "Download failed.\n";
			cleanup();
			return;
		}
	}

	$hash_cmd and do {
		my $sum = `cat "$target/$filename.hash"`;
		$sum =~ /^(\w+)\s*/ or die "Could not generate file hash\n";
		$sum = $1;

		if ($sum ne $file_hash) {
			print STDERR "Hash of the downloaded file does not match (file: $sum, requested: $file_hash) - deleting download.\n";
			cleanup();
			return;
		}
	};

	unlink "$target/$filename";
	move("$target/$filename.dl", "$target/$filename");
	cleanup();
}

sub cleanup
{
	unlink "$target/$filename.dl";
	unlink "$target/$filename.hash";
}

@mirrors = localmirrors();

foreach my $mirror (@ARGV) {
	# 镜像以 @SF 开头，表示从 sourceforge 下载
	if ($mirror =~ /^\@SF\/(.+)$/) {
		# give sourceforge a few more tries, because it redirects to different mirrors
		for (1 .. 5) {
			# $1 是上面if里正则捕获组
			projectsmirrors '@SF', $1;
		}
	} elsif ($mirror =~ /^\@OPENWRT$/) {
		# use OpenWrt source server directly
	} elsif ($mirror =~ /^\@DEBIAN\/(.+)$/) {
		projectsmirrors '@DEBIAN', $1;
	} elsif ($mirror =~ /^\@APACHE\/(.+)$/) {
		projectsmirrors '@APACHE', $1;
	} elsif ($mirror =~ /^\@GITHUB\/(.+)$/) {
		# 加了5个进去，多重试几次
		# give github a few more tries (different mirrors)
		for (1 .. 5) {
			projectsmirrors '@GITHUB', $1;
		}
	} elsif ($mirror =~ /^\@GNU\/(.+)$/) {
		projectsmirrors '@GNU', $1;
	} elsif ($mirror =~ /^\@SAVANNAH\/(.+)$/) {
		projectsmirrors '@SAVANNAH', $1;
	} elsif ($mirror =~ /^\@KERNEL\/(.+)$/) {
		my @extra = ( $1 );
		# 内核区分 rc 和 正式版
		if ($filename =~ /linux-\d+\.\d+(?:\.\d+)?-rc/) {
			push @extra, "$extra[0]/testing";
		} elsif ($filename =~ /linux-(\d+\.\d+(?:\.\d+)?)/) {
			push @extra, "$extra[0]/longterm/v$1";
		}
		foreach my $dir (@extra) {
			projectsmirrors '@KERNEL', $dir;
		}
	} elsif ($mirror =~ /^\@GNOME\/(.+)$/) {
		projectsmirrors '@GNOME', $1;
	} else {
		push @mirrors, $mirror;
	}
}

projectsmirrors '@OPENWRT';

# 如果文件存在，计算hash判断是否匹配
if (-f "$target/$filename") {
	$hash_cmd and do {
		# 生成 hash 文件
		if (system("cat '$target/$filename' | $hash_cmd > '$target/$filename.hash'")) {
			die "Failed to generate hash for $filename\n";
		}

		my $sum = `cat "$target/$filename.hash"`;
		$sum =~ /^(\w+)\s*/ or die "Could not generate file hash\n";
		$sum = $1;

		cleanup();
		exit 0 if $sum eq $file_hash;

		die "Hash of the local file $filename does not match (file: $sum, requested: $file_hash) - deleting download.\n";
		unlink "$target/$filename";
	};
}

# 下载工具
$download_tool = select_tool();

# 如果文件不存在，从镜像下载
while (!-f "$target/$filename") {
	my $mirror = shift @mirrors;
	$mirror or die "No more mirrors to try - giving up.\n";

	download($mirror, $url_filename, @mirrors);
	if (!-f "$target/$filename" && $url_filename ne $filename) {
		download($mirror, $filename, @mirrors);
	}
}

$SIG{INT} = \&cleanup;
