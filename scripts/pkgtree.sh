#! /bin/sh
# Copyright (c) 2012 Bryan Drewery <bryan@shatow.net>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer
#    in this position and unchanged.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR(S) ``AS IS'' AND ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
# OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
# IN NO EVENT SHALL THE AUTHOR(S) BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
# NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
# THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

show_tree() {
	local name=$1
	local indentation=$2
	local parent=$3

	if [ $RECURSIVE -eq 0 -a $indentation -gt 1 ]; then
		return
	fi

	if [ $indentation -eq 0 ]; then
		parent="${name}"
	else
		parent="${parent}% ${name}"
	fi

	echo ${parent}

	for depends in $(pkg ${PKG_QUERY} ${PKG_QUERY_DISPLAY_DEPENDS} ${name} | sort); do
		test -z "${depends}" && return
		show_tree $depends $((${indentation} + 1)) ${parent}
	done
}

usage() {
	echo "Usage: $0 [-nprR] [pkgname|origin] [...]"
	echo "-n: Non-tree view, uses tabs instead"
	echo "-p: Print package names"
	echo "-r: Recursively show required packages"
	echo "-R: Use remote repository"
	echo "-U: Show reverse depends"
	echo "If no package/origin is specified, show all non-automatic packages at top-level."
	exit 0
}

while getopts "hnprRU" opt; do
	case "${opt}" in
		n)
			TREE_VIEW=0
			;;
		p)
			DISPLAY_PKG=1
			;;
		r)
			RECURSIVE=1
			;;
		R)
			USE_RQUERY=1
			;;
		U)
			REVERSE_DEPENDS=1
			;;
		*)
			usage
			;;
	esac
done

shift $(($OPTIND - 1))

: ${RECURSIVE:=0}
: ${REVERSE_DEPENDS:=0}
: ${TREE_VIEW:=1}
: ${USE_RQUERY:=0}
: ${DISPLAY_PKG:=0}

if [ $REVERSE_DEPENDS -eq 0 ]; then
	PKG_QUERY_DEPENDS="d"
else
	PKG_QUERY_DEPENDS="r"
fi

if [ $DISPLAY_PKG -eq 1 ]; then
	PKG_QUERY_DISPLAY="%n-%v"
	PKG_QUERY_DISPLAY_DEPENDS="%${PKG_QUERY_DEPENDS}n-%${PKG_QUERY_DEPENDS}v"
else
	PKG_QUERY_DISPLAY="%o"
	PKG_QUERY_DISPLAY_DEPENDS="%${PKG_QUERY_DEPENDS}o"
fi

if [ $USE_RQUERY -eq 0 ]; then
	PKG_QUERY=query
else
	PKG_QUERY=rquery
fi

main() {
	if [ $# -eq 0 ]; then
		if [ $USE_RQUERY -eq 0 ]; then
			packages=$(pkg ${PKG_QUERY} -e '%a = 0' ${PKG_QUERY_DISPLAY} | sort)
		else
			packages=$(pkg ${PKG_QUERY} ${PKG_QUERY_DISPLAY} | sort)
		fi
	else
		packages=$@
	fi;

	for name in ${packages}; do
		show_tree ${name} 0
	done
}

if [ $TREE_VIEW -eq 1 ]; then
	main $@ | sed -e 's/[^%]*%/|  /g' -e 's/|  \([^|]\)/`--\1/g'
else
	main $@ | sed -e 's/[^%]*%/	/g'
fi
