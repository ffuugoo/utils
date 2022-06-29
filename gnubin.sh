#!/usr/bin/env zsh

set -euo pipefail

declare self=$0
declare repo=${self:A:h}
declare root=${repo:h}

declare gnubin=$root/.env/gnubin

if [[ -e $gnubin ]]
then
	if [[ ! -d $gnubin ]]
	then
		echo "'$gnubin' path exists and is not a directory!" >&2
		exit 1
	fi

	if [[ -e $gnubin~ ]]
	then
		if [[ ! -d $gnubin~ ]]
		then
			echo "'$gnubin~' path exists and is not a directory!" >&2
			exit 2
		fi

		rm -r $gnubin~
	fi

	mv $gnubin $gnubin~
fi

mkdir -p $gnubin

for dir in $(find /usr/local/opt -follow -type d -name gnubin)
do
	for file in $dir/*
	do
		ln -sf $file $gnubin
	done
done
