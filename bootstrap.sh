#!/bin/sh
echo "Bootstrapping main..."
set -x
aclocal
automake --add-missing --copy
autoconf
cd vhffs-fs
./bootstrap.sh
cd ..
