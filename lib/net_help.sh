#!/usr/bin/bash
#
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
#
# Copyright 2012 OmniTI Computer Consulting, Inc.  All rights reserved.
# Copyright 2020 OmniOS Community Edition (OmniOSce) Association.
#

# Returns a mac address as 12 hex characters, upper-case, from the first
# non-loopback interface in the system.
Ether() {
    local mac="`/sbin/dladm show-phys -m -p -o ADDRESS | \
        /bin/tr '[:lower:]' '[:upper:]' | \
        sed '
            s/^/ 0/g
            s/:/ 0/g
            s/0\([0-9A-F][0-9A-F]\)/\1/g
            s/ //g
            q
        '`"

    log "Ether() = $mac"
    echo $mac
}

UseDNS() {
    log "UseDNS: $*"

    server=$1; shift
    domain=$1
    EnableDNS $domain $*
    SetDNS $server
}

EnableDNS() {
    log "EnableDNS: $*"

    domain=$1
    if [ -n "$domain" ]; then
        cat <<EOF > $ALTROOT/etc/resolv.conf
domain $domain
search $*
EOF
    fi
    logcmd cp $ALTROOT/etc/nsswitch.{dns,conf}
}

SetDNS() {
    log "SetDNS: $*"

    /usr/bin/egrep -s 'files dns' $ALTROOT/etc/nsswitch.conf || EnableDNS

    for srv in $*; do
        echo nameserver $srv >> $ALTROOT/etc/resolv.conf
    done
}

# Vim hints
# vim:ts=4:sw=4:et:fdm=marker
