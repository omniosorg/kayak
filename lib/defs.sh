# {{{ CDDL HEADER
#
# This file and its contents are supplied under the terms of the
# Common Development and Distribution License ("CDDL"), version 1.0.
# You may only use this file in accordance with the terms of version
# 1.0 of the CDDL.
#
# A full copy of the text of the CDDL should have accompanied this
# source. A copy of the CDDL is also available via the Internet at
# http://www.illumos.org/license/CDDL.
# }}}

# Copyright 2023 OmniOS Community Edition (OmniOSce) Association.

# This library used by both ksh and bash scripts, don't use any bash extensions.

OOCEVER=`awk -F= '$1 == "VERSION" { print $2 }' /etc/os-release`
OOCEREL="${OOCEVER//[a-z]/}"

OOCEPUB=omnios
EXTRAPUB=extra.omnios

URLPREFIX=https://pkg.omnios.org

MIRRORS=us-west
MIRRORDOMAIN=mirror.omnios.org

if (( OOCEREL % 2 == 0 )); then
    URLSUFFIX=r$OOCEREL/core
else
    URLSUFFIX=bloody/core
fi
OOCEPUBURL=$URLPREFIX/$URLSUFFIX
OOCEPUBURL_EXTRA="${OOCEPUBURL/core/extra}"

OOCEBRAICHURL=$URLPREFIX/bloody/braich

PYTHONVER=3.15
PYTHONPKGVER=${PYTHONVER//./}

DEFPATH=/usr/bin:/usr/sbin:/sbin:/usr/gnu/bin
DEFSUPATH=/usr/sbin:/sbin:/usr/bin
EXTRAPATH=/usr/bin:/usr/sbin:/sbin:/opt/ooce/bin:/usr/gnu/bin
EXTRASUPATH=/usr/sbin:/sbin:/opt/ooce/sbin:/usr/bin:/opt/ooce/bin

NATIVE_SVCCFG=usr/src/tools/proto/root_i386-nd/opt/onbld/bin/i386/svccfg

# Vim hints
# vim:ts=4:sw=4:et:fdm=marker
