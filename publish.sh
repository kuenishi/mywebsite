#!/bin/sh

set -eux

SRC=build/html

rm -rf kuenishi.github.com/_static
rm -rf kuenishi.github.com/_sources
rm -rf kuenishi.github.com/memo
cp -r $SRC/* kuenishi.github.com
cd kuenishi.github.com
git add -A
#.html
#git add memo/*.html
#git add _static/*
#git add _sources/*
#git add _sources/memo/*
#git add _images/*
git commit -S -m "autocommit by publish.sh"
#git push origin master


