#!/bin/sh
echo "Bootstrapping vhffs-fs..."
set -x
aclocal
automake --add-missing --copy
autoconf
