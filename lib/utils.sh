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

function check_hostname {
    echo $1 | egrep -s '^[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9]$'
}

function t_prompt_hostname {
    NEWHOST="$1"
    while [ -n "$NEWHOST" ]; do
        HOSTNAME="$NEWHOST"
        echo -n "Please enter a hostname or press RETURN if you want [$HOSTNAME]: "
        read NEWHOST
        [ -z "$NEWHOST" ] && break
        check_hostname "$NEWHOST" && continue
        echo "Invalid hostname - $NEWHOST"
        NEWHOST=$HOSTNAME
    done
}

function d_prompt_hostname {
    HOSTNAME="$1"
    while :; do
        dialog \
            --title "Enter the system hostname" \
            --inputbox '' 7 40 "$HOSTNAME" 2> $tmpf
        [ $? -ne 0 ] && exit 0
        HOSTNAME="`cat $tmpf`"
        rm -f $tmpf
        [ -z "$HOSTNAME" ] && continue
        check_hostname "$HOSTNAME" && break
        d_msg "Invalid hostname"
    done
}

function prompt_hostname {
    [ -n "$USE_DIALOG" ] && d_prompt_hostname "$@" || t_prompt_hostname "$@"
    log "Selected hostname: $HOSTNAME"
}

function t_prompt_timezone {
    tzselect |& tee /tmp/tz.$$
    TZ="`tail -1 /tmp/tz.$$`"
    rm -f /tmp/tz.$$
}

function d_prompt_timezone {
    # Select a timezone.
    /kayak/installer/dialog-tzselect /tmp/tz.$$
    TZ="`tail -1 /tmp/tz.$$`"
    rm -f /tmp/tz.$$
}

function prompt_timezone {
    [ -n "$USE_DIALOG" ] && d_prompt_timezone "$@" || t_prompt_timezone "$@"
    log "Selected timezone: $TZ"
}

function runsvccfg {
    log "runsvccfg: $*"

    LD_LIBRARY_PATH=$ALTROOT/lib:$ALTROOT/usr/lib \
        SVCCFG_DTD=$ALTROOT/usr/share/lib/xml/dtd/service_bundle.dtd.1 \
        SVCCFG_REPOSITORY=$ALTROOT/etc/svc/repository.db \
        logcmd $ALTROOT/usr/sbin/svccfg "$@"
}

function runpkg {
    log "runpkg: $*"
    LD_LIBRARY_PATH=$ALTROOT/usr/lib/amd64 \
        PYTHONPATH=$ALTROOT/usr/lib/pkg/python3.13:$ALTROOT/usr/lib/python3.13/vendor-packages \
        $ALTROOT/usr/bin/python3.13 \
        $ALTROOT/usr/bin/pkg -R $ALTROOT "$@" | pipelog
    sed -i '/^last_uuid/d' $ALTROOT/var/pkg/pkg5.image
}

function setpaths {
    typeset root="${1?altroot}"; shift
    typeset defpath="${1?defpath}"; shift
    typeset supath="${1?supath}"; shift

    sed -i~ "
        /^#*PATH=/c\\
PATH=$defpath
        /^#*SUPATH=/c\\
SUPATH=$supath
    " $root/etc/default/login $root/etc/default/su
}

function extrarepo {
    log "extrarepo $1"

    case $1 in
        -off)
            runpkg unset-publisher $EXTRAPUB
            setpaths $ALTROOT $DEFPATH $DEFSUPATH
            ;;
        *)
            runpkg set-publisher --no-refresh -O $OOCEPUBURL_EXTRA $EXTRAPUB
            for m in $MIRRORS; do
                runpkg set-publisher --no-refresh \
                    -m https://$m.$MIRRORDOMAIN/${URLSUFFIX/core/extra} \
                    $EXTRAPUB
            done
            runpkg publisher $OOCEPUB | egrep -s require-signatures &&
                runpkg set-publisher --no-refresh --set-property \
                signature-policy=require-signatures $EXTRAPUB
            setpaths $ALTROOT $EXTRAPATH $EXTRASUPATH
            ;;
    esac

    log "--- final publisher configuration ---"
    runpkg publisher
}

function cloudinit_pkg {
    case $1 in
        -off)
            log "Uninstalling cloud-init package..."
            runpkg uninstall --no-index cloud-init
            ;;
        *)
            log "Installing cloud-init package..."
            runpkg install --no-refresh --no-index \
                -g /.cdrom/image/p5p/cloud-init.p5p cloud-init
            ;;
    esac
}

function logadm_rsyslog {
    typeset altroot="${1:?altroot}"

    sed -i '
        s^/var/run/syslog.pid^/var/run/rsyslogd.pid^
    ' $altroot/etc/logadm.conf
}

function apply_custom_overlay {
    typeset custom_overlay="$1"
    typeset workdir="$2"

    [ -z "$custom_overlay" ] && return 0
    [ ! -d "$custom_overlay" ] && return 0

    echo " --- applying custom overlay from $custom_overlay"

    typeset -i file_count=0
    typeset -i dir_count=0

    file_count=`cd "$custom_overlay" && find . -type f | wc -l`
    dir_count=`cd "$custom_overlay" && find . -type d | wc -l`

    pushd "$custom_overlay" >/dev/null
    find . | cpio -pdum "$workdir" 2>&1 >/dev/null || {
        echo " WARNING: Failed to apply overlay completely"
        popd >/dev/null
        return 1
    }

    popd >/dev/null
    echo " Applied $file_count file(s) from $dir_count directories"
}

# Vim hints
# vim:ts=4:sw=4:et:fdm=marker
