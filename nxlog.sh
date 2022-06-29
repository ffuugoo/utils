#!/usr/bin/env zsh

set -euo pipefail -o nullglob -o globdots


declare self=$0
declare repo=${self:A:h}
declare root=${repo:h}

declare env=$root/.env

declare nxlog=$root/nxlog
declare rust=$nxlog/rust

declare addons=$root/nxlog-addons
declare msazure=$addons/msazure

declare xcc=xcc-0.5.3


function nxlog {
	prepare
}

function clone {
	cd $root

	declare branch=${branch:-}

	if [[ ! -e nxlog ]]
	then
		git clone git@gitlab.com:nxlog/nxlog.git ${branch:+--branch} ${branch:-}
	fi
}

function configure {
	if [[ -e $nxlog/Makefile ]]
	then
		return 0
	fi

	clone

	cd $nxlog

	if [[ ! -e configure ]]
	then
		./autogen.sh --help
	fi

	if whence -p sccache &>/dev/null
	then
		export CXX="sccache gcc -fdiagnostics-color=always"
		export CC="sccache gcc -fdiagnostics-color=always"
	fi

	CPPFLAGS="-DDEBUG ${CPPFLAGS:-}" \
	CXXFLAGS='-g -O0' \
	CFLAGS='-g -O0' \
	LDFLAGS="${LDFLAGS:-}"
	./configure \
		--prefix=$env/nxlog \
		\
		--disable-static \
		--enable-shared \
		${install:+--disable-dependency-tracking} \
		${install:+--enable-fast-install} \
		\
		--disable-documentation \
		--disable-hardening \
		\
		--disable-bsm \
		--disable-checkpoint \
		--disable-dbi \
		--disable-im_maces \
		--disable-im_pcap \
		--disable-java \
		--disable-kafka \
		--disable-kerberos \
		--disable-odbc \
		--disable-xm_perl \
		--disable-xm_python \
		--disable-xm_ruby \
		--disable-zmq
}

function prepare {
	configure

	cd $nxlog

	make -C src/common expr-tokens.c expr-grammar.c expr-grammar.h expr-core-funcproc.c expr-core-funcproc.h

	if [[ ! -e compile_commands.json ]]
	then
		if whence -p compiledb &>/dev/null
		then
			compiledb --no-build -- make
			compdb-list
		fi
	fi

	make -C src/common libnx.la
}

function build {
	xcc

	configure

	cd $nxlog

	if declare wrapper && wrapper="$(make-wrapper)" && [[ $wrapper != '' ]]
	then
		rm -f compile_commands.json
		$wrapper -- make
		compdb-list
	else
		make
	fi
}

function install {
	if whence -p nxlog &>/dev/null
	then
		return 0
	fi

	install=1 build

	cd $nxlog

	make install
	mkdir -p $prefix/var/{run,spool}/nxlog
}

function distclean {
	if [[ ! -d $nxlog ]]
	then
		return 1
	fi

	cd $nxlog

	if [[ -f Makefile ]]
	then
		make-distclean
	fi
}


function rust {
	prepare

	cd $rust

	if [[ ! -e nxlog-module-sys/nxlog ]]
	then
		ln -sf $nxlog nxlog-module-sys/nxlog
	fi

	cargo build --all
	cargo build -p nxlog-wrapper --bin nxlog-wrapper

	cargo check --all
	cargo check -p nxlog-wrapper --bin nxlog-wrapper

	cargo clippy --all || :
	cargo clippy -p nxlog-wrapper --bin nxlog-wrapper || :
}


function addons {
	addons-clone

	cd $msazure

	cargo build
	cargo check
	cargo clippy || :
}

function addons-clone {
	cd $root

	declare branch=${branch:-}

	git clone git@gitlab.com:nxlog/nxlog-addons.git --no-checkout ${branch:+--branch} ${branch:-}

	cd $addons

	git sparse-checkout init
	git sparse-checkout set 'msazure/*' 'rust/*'
	git checkout
}


function workspace {
	for src in $repo/workspace/*
	do
		declare dst=$root/${src:t}

		if [[ -L $dst ]]
		then
			rm $dst
		fi

		if [[ -e $dst ]]
		then
			echo "'$dst' already exists (and is not a symlink)!" >&2
			return 1
		fi

		ln -s $src $dst
	done
}


function xcc {
	if whence -p xcc &>/dev/null
	then
		return 0
	fi

	xcc-prepare

	cd $root/$xcc

	if [[ ! -e configure ]]
	then
		autoreconf --install
	fi

	if [[ ! -e Makefile ]]
	then
		./configure \
			--prefix=$env/xcc \
			\
			--disable-static \
			--enable-shared \
			\
			--disable-dependency-tracking \
			--enable-fast-install
	fi

	make

	make install

	xcc-cleanup
}

function xcc-prepare {
	if [[ -e $root/$xcc ]]
	then
		return 0
	fi

	clone

	cd $root

	if [[ ! -e $xcc.tar.gz ]]
	then
		tar -xf nxlog/packaging/$xcc.tar.bz2 --strip-components=1 xcc-cvs/$xcc.tar.gz
	fi

	tar -xf $xcc.tar.gz

	cd $root/$xcc

	mv configure.in configure.ac

	autoupdate
	autoreconf --install

	autoupdate
	autoreconf --install

	./configure

	make-distclean
}

function xcc-cleanup {
	rm -rf $root/$xcc $root/$xcc.tar.gz
}


function make-wrapper {
	for wrapper in compiledb bear
	do
		if whence -p $wrapper &>/dev/null
		then
			echo $wrapper
			return 0
		fi
	done

	return 1
}

function compdb-list {
	if [[ -f compile_commands.json ]]
	then
		if whence -p compdb &>/dev/null
		then
			compdb list > compile_commands_with_headers.json
			mv compile_commands_with_headers.json compile_commands.json
		fi
	fi
}

function make-distclean {
	make distclean
	rm -rf autom4te.cache
}


if [[ $ZSH_EVAL_CONTEXT == toplevel ]] && (( $# == 0 ))
then
	nxlog
else
	$@
fi
