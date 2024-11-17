#!/usr/bin/env bash
export LANG=C
export LC_ALL=C

if [ -n "$TOPDIR" ]; then
	cd "$TOPDIR" || exit 1
fi

# :- 是参数拓展运算符，如果 $1 为空，则使用 . 作为默认值
SOURCE="${1:-.}"

try_version() {
	[ -f "$SOURCE/version.date" ] || return 1
	SOURCE_DATE_EPOCH=$(cat "$SOURCE/version.date")
	[ -n "$SOURCE_DATE_EPOCH" ]
}

try_git() {
	SOURCE_DATE_EPOCH=$(git -C "$SOURCE" log -1 --no-show-signature \
		--format=format:%ct "$SOURCE" 2>/dev/null)
	[ -n "$SOURCE_DATE_EPOCH" ]
}

try_hg() {
	SOURCE_DATE_EPOCH=$(hg --cwd "$SOURCE" log --template '{date}' -l 1 \
		"$SOURCE" 2>/dev/null | cut -d. -f1)
	[ -n "$SOURCE_DATE_EPOCH" ]
}

try_mtime() {
	SOURCE_DATE_EPOCH=$(perl -e 'print((stat $ARGV[0])[9])' "$0")
	[ -n "$SOURCE_DATE_EPOCH" ]
}

try_version || try_git || try_hg || try_mtime || SOURCE_DATE_EPOCH=""
echo "$SOURCE_DATE_EPOCH"
