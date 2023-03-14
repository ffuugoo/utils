#!/usr/bin/env zsh

set -euo pipefail


declare toolchains=( stable nightly )
declare components=( rust-src )

declare tools=(
	${=tools:+cargo-expand cargo-nextest}
	${=linters:+cargo-audit cargo-deny cargo-spellcheck}
	${sccache:+sccache}
)

declare toolchain=${toolchain:-${toolchains[1]:-stable}}
declare opts=( ${${:---component}:^^components} )


function install {
	declare opts=( ${@:-$opts} )

	if ! whence -p cargo &>/dev/null
	then
		install-rust $opts
	fi

	if whence -p rustup &>/dev/null
	then
		install-toolchains $opts
	fi

	install-tools

	setup-rust
}

function install-rust {
	declare opts=( ${@:-$opts} )

	if whence -p rustup &>/dev/null
	then
		rustup toolchain install $toolchain $opts
	else
		install-rustup $opts
	fi
}

function install-rustup {
	declare opts=( -y --no-modify-path --default-toolchain $toolchain ${@:-$opts} )

	if whence -p rustup-init &>/dev/null
	then
		rustup-init $opts
	else
		curl -sSf https://sh.rustup.rs | sh -s -- $opts
	fi
}

function install-toolchains {
	declare opts=( ${@:-$opts} )

	for toolchain in $toolchains
	do
		rustup toolchain install $toolchain $opts
	done
}

function install-tools {
	declare tools=( ${@:-$tools} )

	for tool in $tools
	do
		if ! whence -p $tool &>/dev/null
		then
			cargo install $tool
		fi
	done
}

function setup-rust {
	setup-sccache
	setup-ld
}

function setup-sccache {
	if whence -p sccache &>/dev/null
	then
		cargo-config <<-EOF
		[build]
		rustc-wrapper = "sccache"
		EOF
	fi
}

function setup-ld {
	setup-mold || setup-lld || :
}

function setup-mold {
	try-setup-ld mold
}

function setup-lld {
	try-setul-ld lld
}

function try-setup-ld {
	declare target="$(rustup show | grep 'Default host' | sed -E 's|Default host: ||')"
	declare ld=$1

	if [[ $target == '' ]]
	then
		return 0
	fi

	if ! whence -p $ld &>/dev/null
	then
		return 1
	fi

	cargo-config <<-EOF
	[target.$target]
	linker = "clang"
	rustflags = ["-C", "link-arg=-fuse-ld=$ld"]
	EOF
}

function cargo-config {
	declare cargo=~/.cargo/config.toml

	declare config="$(cat)"
	declare header="$(head -n 1 <<< $config)"

	if ! grep -F $header $cargo &>/dev/null
	then
		printf '%s\n\n' $config >> $cargo
	fi
}


function uninstall {
	rm -rf ~/.cargo ~/.rustup ~/.cache/sccache ~/Library/Caches/Mozilla.sccache
}


if [[ $ZSH_EVAL_CONTEXT == toplevel ]] && (( $# == 0 ))
then
	install
else
	$@
fi
