#!/usr/bin/env zsh

set -euo pipefail -o nullglob -o globdots


declare self=$0
declare repo=${self:A:h}
declare root=${repo:h}

declare env=$root/.env

declare nxlog=$root/nxlog
declare build=$nxlog/build

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
	if [[ -f $build/CMakeCache.txt || -f $nxlog/Makefile ]]
	then
		return 0
	fi

	clone

	if [[ -f $nxlog/CMakeLists.txt && -z ${prepare:-} ]]
	then
		configure-cmake
	else
		configure-autotools
	fi
}

function configure-cmake {
	mkdir -p $build

	cd $build

	cmake .. \
	\
	-G ${${prepare:+'Unix Makefiles'}:-Ninja} \
	-DCMAKE_BUILD_TYPE=Debug \
	-DCMAKE_INSTALL_PREFIX=$env/nxlog \
	\
	${prepare:+-DCMAKE_EXPORT_COMPILE_COMMANDS=YES} \
	\
	-DNX_MAKE_DBI_MODULES=NO \
	-DNX_MAKE_ODBC_MODULES=NO \
	-DNX_MAKE_GO_MODULES=NO \
	-DNX_MAKE_JAVA_MODULES=NO \
	-DNX_MAKE_PERL_MODULES=NO \
	-DNX_MAKE_PYTHON_MODULES=NO \
	-DNX_MAKE_RUBY_MODULES=NO \
	-DNX_MAKE_KAFKA_MODULES=NO \
	-DNX_MAKE_ZMQ_MODULES=NO \
	\
	-DNX_MAKE_ACCT=NO \
	-DNX_MAKE_BSM=NO \
	-DNX_MAKE_CHECKPOINT_MODULE=NO \
	-DNX_MAKE_KERNEL_MODULE=NO \
	-DNX_MAKE_LINUXAUDIT=NO \
	-DNX_MAKE_PCAP_MODULE=NO \
	\
	-DNX_MAKE_WSEVENTING_MODULE=NO \
	\
	-DNX_MAKE_MACES_MODULE=NO \
	\
	-DNX_MAKE_RUST=NO

	compdb-list

	cd $nxlog

	if [[ -f $build/compile_commands.json ]]
	then
		ln -sf $build/compile_commands.json
	fi
}

function configure-autotools {
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
		--disable-odbc \
		--disable-dbi \
		--disable-java \
		--disable-xm_perl \
		--disable-xm_python \
		--disable-xm_ruby \
		--disable-kafka \
		--disable-zmq \
		\
		--disable-bsm \
		--disable-checkpoint \
		--disable-im_pcap \
		\
		--disable-kerberos \
		\
		--disable-im_maces
}

function prepare {
	prepare=1 configure

	if [[ -f $build/CMakeCache.txt ]]
	then
		prepare-cmake
	else
		prepare-autotools
	fi
}

function prepare-cmake {
	cd $nxlog/build

	ninja-make nx_shared
}

function prepare-autotools {
	cd $nxlog

	make -C src/common \
		libnx.la \
		expr-tokens.c \
		expr-grammar.c expr-grammar.h \
		expr-core-funcproc.c expr-core-funcproc.h

	if [[ ! -e compile_commands.json ]]
	then
		rm -f compile_commands.json

		if whence -p compiledb &>/dev/null
		then
			compiledb --no-build -- make
			compdb-list
		fi
	fi
}

function build {
	xcc

	configure

	if [[ -f $build/CMakeCache.txt ]]
	then
		build-cmake
	else
		build-autotools
	fi
}

function build-cmake {
	cd $nxlog/build

	ninja-make
}

function build-autotools {
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

	if [[ -f $build/CMakeCache.txt ]]
	then
		install-cmake
	else
		install-autotools
	fi

	mkdir -p $env/nxlog/var/{run,spool}/nxlog
}

function install-cmake {
	cd $nxlog/build

	ninja-make install
}

function install-autotools {
	cd $nxlog

	make install
}

function distclean {
	if [[ ! -d $nxlog ]]
	then
		return 1
	fi

	cd $nxlog

	if [[ -d build ]]
	then
		rm -r build
	fi

	if [[ -f Makefile ]]
	then
		make-distclean
	fi
}


function rust {
	prepare

	cd $rust

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


function ninja-make {
	if [[ $* != install ]]
	then
		declare j1= jnproc=1
	else
		declare j1=1 jnproc=
	fi

	if [[ -e build.ninja ]]
	then
		ninja ${j1:+-j1} $@
	else
		make ${jnproc:+-j$(nproc)} $@
	fi
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
