#!/bin/bash

deploy() {
	cd $1
	revision=`git rev-parse HEAD`
	if [ -n "$FORCE" -a -n "$revision" ]; then
		rm -rf $2/build
	fi
}
