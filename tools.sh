#!/usr/bin/env zsh

set -euo pipefail


declare python=( compiledb compdb )


function install {
	python-install
}

function uninstall {
	python-uninstall
}


function python-install {
	declare tools=( ${@:-$python} )

	for tool in $python
	do
		pip-install $tool
	done
}

function python-uninstall {
	declare tools=( ${@:-$python} )

	for tool in $python
	do
		pip-uninstall $tool || :
	done
}


function pip-install {
	declare tool=$1

	if ! which $tool &>/dev/null
	then
		pip install --user $tool
	fi
}

function pip-uninstall {
	declare tool=$1

	if declare dir && dir="$(which $tool 2>/dev/null)" && [[ $dir == $HOME/.local/bin/* ]]
	then
		pip uninstall $tool
	fi
}


if [[ $ZSH_EVAL_CONTEXT == toplevel ]] && (( $# == 0 ))
then
	install
else
	$@
fi
