#!/usr/bin/env zsh

set -euo pipefail


declare python=(
	${=cpp:+compiledb compdb}
	${=qdrant:+pytest requests qdrant-client}
)


function install {
	python-install
}

function uninstall {
	python-uninstall
}


function python-install {
	for tool in ${@:-$python}
	do
		pip-install $tool
	done
}

function python-uninstall {
	for tool in ${@:-$python}
	do
		pip-uninstall $tool || :
	done
}


function pip-install {
	declare tool=$1

	if ! whence -p $tool &>/dev/null
	then
		pip3 install --user $tool
	fi
}

function pip-uninstall {
	declare tool=$1

	if declare dir && dir="$(whence -p $tool 2>/dev/null)" && [[ $dir == $HOME/.local/bin/* ]]
	then
		pip3 uninstall $tool
	fi
}


if [[ $ZSH_EVAL_CONTEXT == toplevel ]] && (( $# == 0 ))
then
	install
else
	$@
fi
