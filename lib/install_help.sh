#!/usr/bin/bash

# {{{ CDDL licence header
#
# This file and its contents are supplied under the terms of the
# Common Development and Distribution License ("CDDL"), version 1.0.
# You may only use this file in accordance with the terms of version
# 1.0 of the CDDL.
#
# A full copy of the text of the CDDL should have accompanied this
# source.  A copy of the CDDL is also available via the Internet at
# http://www.illumos.org/license/CDDL.
#
# }}}

#
# Copyright 2017 OmniTI Computer Consulting, Inc.  All rights reserved.
# Copyright 2020 OmniOS Community Edition (OmniOSce) Association.
#

INSTALL_LOG=

set -o pipefail

# Open the kayak log file at the provided path and open file descriptor 4
# for output to it.
SetupLog() {
    [ -n "$INSTALL_LOG" ] && return
    INSTALL_LOG=$1
    exec 4>>$INSTALL_LOG
}

# Check to see if this system has an rpool. We want to guard against install
# over an already configured system should it accidentally PXE boot.
FailIfRpoolExists() {
    zpool import -a
    res=`zpool list | grep rpool`

    if [[ "$?" -eq "0" ]]; then
        bomb "This is an installed system. To reinstall, destroy rpool and reboot."
    fi
}

# Set up logging so that log messages go to the console and that stdout/stderr
# go to a log file at the provided path.
ConsoleLog() {
    [ -n "$INSTALL_LOG" ] && return
    exec 4>/dev/console
    exec 1>>$1
    exec 2>>$1
    INSTALL_LOG=$1
}

CopyInstallLog() {
    [ -n "$INSTALL_LOG" ] && cp $INSTALL_LOG $ALTROOT/var/log/kayak.log
}

SendInstallLog() {
    [ -n "$INSTALL_LOG" ] || return
    PUTURL=`echo $CONFIG | sed -e 's%/kayak/%/kayaklog/%g;'`
    PUTURL=`echo $PUTURL | sed -e 's%/kayak$%/kayaklog%g;'`
    curl -T $INSTALL_LOG $PUTURL/$ETHER
}

# Log a message to the log file.
# Parameters:
#   -o  Also output the log message to stderr
log() {
    [ -n "$INSTALL_LOG" ] || return

    local oflag=0
    [ "$1" = "-o" ] && shift && oflag=1

    TS=`date +%Y/%m/%d-%H:%M:%S`

    echo "[$TS] $*" 1>&4
    [ $oflag -eq 1 ] && echo "[$TS] $*" 1>&2
}

# Log a command and its output.
# If you want to have the output preserved in a pipline, use pipelog() instead
# Parameters:
#   -o  Also output to stderr
logcmd() {
    if [ "$1" = "-o" ]; then
        shift
        log -o "Running: $@"
        "$@" 2>&1 | tee /dev/fd/4 1>&2
        stat=$?
    else
        log "Running: $@"
        "$@" 1>&4 2>&4
        stat=$?
        [ $stat -eq 0 ] || log "Exit status: $stat"
    fi
    return $stat
}

# Copy stdout to the log file (for use in a pipeline)
pipelog() {
    tee /dev/fd/4
}

# Selective log. If in a dialogue environment, show the message in a popup
# window, otherwise on stdout.
slog() {
    if [ -n "$USE_DIALOG" ]; then
        log "$@"
        d_info "$@"
    else
        log -o "$@"
    fi
}

bomb() {
    log -o ""
    log -o ======================================================
    log -o "$*"
    log -o ======================================================
    if [ -n "$INSTALL_LOG" ]; then
        log -o "For more information, check $INSTALL_LOG"
        log -o ======================================================
    fi
    echo $* > /tmp/INSTALLATION_FAILED
    # Pause
    read a
    exit 1
}

. /kayak/lib/net_help.sh
. /kayak/lib/disk_help.sh

ICFILE=/tmp/_install_config
getvar() {
    log "getvar($1)"
    prtconf -v /devices | sed -n '/'$1'/{;n;p;}' | cut -f2 -d\' | pipelog
}

# Blank
ROOTPW='$5$kr1VgdIt$OUiUAyZCDogH/uaxH71rMeQxvpDEY2yX.x0ZQRnmeb9'
RootPW() {
    log "Setting root password hash to $1"
    ROOTPW="$1"
}

SetRootPW(){
    log "Setting root password in shadow file"
    logcmd sed -i -e 's%^root::%root:'$ROOTPW':%' $ALTROOT/etc/shadow
}

ForceDHCP(){
    log "Forcing all interfaces into DHCP..."
    logcmd /sbin/ifconfig -a plumb
    # for the logs
    for iface in `/sbin/dladm show-phys -o device -p` ; do
        logcmd /sbin/ifconfig $iface dhcp &
    done
    while [ -z "`/sbin/dhcpinfo BootSrvA`" ]; do
        log "Waiting for dhcpinfo..."
        sleep 1
    done
    BOOTSRVA=`/sbin/dhcpinfo BootSrvA`
    log "Next server: $BOOTSRVA"
    sleep 1
}

BE_Create_Root() {
    local _rpool="${1:?rpool}"

    log "Creating root BE"
    [ -z "$NO_COMPRESSION" ] && logcmd zfs set compression=on $_rpool
    logcmd zfs create $_rpool/ROOT
    logcmd zfs set canmount=off $_rpool/ROOT
    logcmd zfs set mountpoint=legacy $_rpool/ROOT
}

BE_Receive_Image() {
    local _grab="${1:?grab}"
    local _decomp="${2:?decomp}"
    local _rpool="${3:?rpool}"
    local _bename="${4:?bename}"
    local _media="${5:?media}"

    slog "Preparing to install ZFS image"
    pv="pv -B 128m"
    [ "$_grab" = cat ] && pv+=" -s `ls -lh $_media | awk '{print $5}'`"

    if [ -n "$USE_DIALOG" ]; then
        ($_grab $_media | $pv -n | $_decomp \
            | zfs receive -u $_rpool/ROOT/$_bename) 2>&1 \
            | dialog --gauge 'Installing ZFS image' 7 70
    else
        $_grab $_media | $pv -w 78 | $_decomp | \
            zfs receive -u $_rpool/ROOT/$_bename 2>&4
    fi
    logcmd zfs set canmount=noauto $_rpool/ROOT/$_bename
    logcmd zfs set mountpoint=legacy $_rpool/ROOT/$_bename
}

BE_Mount() {
    local _rpool=${1:?rpool}
    local _bename=${2:?bename}
    local _root=${3:?root}
    local _method${4:-beadm}

    slog "Mounting BE $_bename on $_root"

    if [ "$_method" = beadm ]; then
        logcmd beadm mount $_bename $_root
    else
        logcmd mount -F zfs $_rpool/ROOT/$_bename $_root
    fi
    export ALTROOT=$_root
}

BE_Umount() {
    local _bename=${1:?bename}
    local _root=${2:?root}
    local _method${3:-beadm}

    slog "Unmounting BE $_bename"
    if [ "$_method" = beadm ]; then
        logcmd beadm umount $_bename
    else
        logcmd umount $_root
    fi
}

BE_SetUUID() {
    local _rpool=${1:?rpool}
    local _bename=${2:?bename}
    local _root=${3:?root}

    local uuid=`LD_LIBRARY_PATH=$_root/lib:$_root/usr/lib \
        $_root/usr/bin/uuidgen`

    slog "Setting BE $_bename UUID: $uuid"
    logcmd zfs set org.opensolaris.libbe:uuid=$uuid $_rpool/ROOT/$_bename
    logcmd zfs set org.opensolaris.libbe:policy=static $_rpool/ROOT/$_bename
}

BE_LinkMsglog() {
    local _root=${1:?root}

    logcmd /usr/sbin/devfsadm -r $_root
    [ -L "$_root/dev/msglog" ] || \
        logcmd ln -s ../devices/pseudo/sysmsg@0:msglog $_root/dev/msglog
}

BuildBE() {
    RPOOL=${1:-rpool}
    local MEDIA="$2"
    local _bename=${3:-omnios}

    if [ -z "$MEDIA" ]; then
        BOOTSRVA=`/sbin/dhcpinfo BootSrvA`
        MEDIA=`getvar install_media`
        MEDIA=`echo $MEDIA | sed -e "s%//\:%//$BOOTSRVA\:%g;"`
        MEDIA=`echo $MEDIA | sed -e "s%///%//$BOOTSRVA/%g;"`
        GRAB="curl -s"
    else
        GRAB=cat
    fi
    DECOMP="bzip2 -dc"      # Old default
    case $MEDIA in
        *.xz)       DECOMP="xz -dc" ;;
        *.bz2)      DECOMP="bzip2 -dc" ;;
        *.gz)       DECOMP="gzip -dc" ;;
    esac

    BE_Create_Root $RPOOL
    BE_Receive_Image "$GRAB" "$DECOMP" $RPOOL $_bename $MEDIA
    BE_Mount $RPOOL $_bename /mnt
    BE_SetUUID $RPOOL $_bename /mnt
    BE_LinkMsglog /mnt
    MakeSwapDump
    MakeExportHome $RPOOL
    Postboot "zpool set cachefile=/etc/zfs/zpool.cache $RPOOL"
    logcmd zfs destroy $RPOOL/ROOT/$_bename@kayak
}

FetchConfig(){
    ETHER=`Ether`
    BOOTSRVA=`/sbin/dhcpinfo BootSrvA`
    CONFIG=`getvar install_config`
    CONFIG=`echo $CONFIG | sed -e "s%//\:%//$BOOTSRVA\:%g;"`
    CONFIG=`echo $CONFIG | sed -e "s%///%//$BOOTSRVA/%g;"`
    L=${#ETHER}
    log "Fetching configuration"
    while [ "$L" -gt "0" ]; do
        URL="$CONFIG/${ETHER:0:$L}"
        log "... trying $URL"
        logcmd /bin/curl -s -o $ICFILE $URL
        if [ -f "$ICFILE" ]; then
            if egrep -s BuildRpool $ICFILE; then
                log "Successfully fetched configuration"
                return 0
            fi
            rm -f $ICFILE
        fi
        ((L = L - 1))
    done
    log "Failed to fetch configuration"
    return 1
}

MakeBootable(){
    local _rpool=${1:-rpool}
    local _bename=${2:-omnios}
    slog "Making boot environment bootable"
    logcmd zpool set bootfs=$_rpool/ROOT/$_bename $_rpool
    # Must do beadm activate first on the off chance we're bootstrapping from
    # GRUB.
    slog "Activating BE"
    logcmd beadm activate $_bename || return 1
    slog "Installing bootloader"
    logcmd bootadm install-bootloader -Mf -P $_rpool || return 1
    slog "Updating boot archive"
    logcmd bootadm update-archive -R $ALTROOT || return 1
    return 0
}

SetHostname() {
    log "Setting hostname: $1"
    logcmd /bin/hostname "$1"
    echo "$1" > $ALTROOT/etc/nodename
    cat <<- EOM > $ALTROOT/etc/inet/hosts
		# Host table
		::1		localhost $1.local $1
		127.0.0.1	localhost loghost $1.local $1
	EOM
}

AutoHostname() {
    suffix=$1
    macaddr=`/sbin/ifconfig -a | /usr/bin/nawk '
        /UP/ && $2 !~ /LOOPBACK/ { iface = $1 }
        /ether/ && iface { print $2; exit }
        ' | /bin/tr '[:upper:]' '[:lower:]' | \
        /bin/sed -e 's/^/ 0/g;s/:/-0/g; s/0\([0-9a-f][0-9a-f]\)/\1/g; s/ //g;'`
    [ -z "$suffix" ] && suffix=omnios
    [ "$suffix" = "-" ] && suffix= || suffix=-$suffix
    SetHostname $macaddr$suffix
}

SetTimezone() {
    log "Setting timezone: $1"
    logcmd sed -i -e "s:^TZ=.*:TZ=$1:" $ALTROOT/etc/default/init
}

SetLang() {
    log "Setting language: $1"
    logcmd sed -i -e "s:^LANG=.*:LANG=$1:" $ALTROOT/etc/default/init
}

SetKeyboardLayout() {
    # Put the new keyboard layout ($1) in
    # "setprop keyboard-layout <foo>" in the newly-installed root's
    # /boot/solaris/bootenv.rc (aka. eeprom(1M) storage for amd64/i386).
    layout=$1
    log "Setting keyboard layout to $layout"
    logcmd sed -i "s/keyboard-layout Unknown/keyboard-layout $layout/g" \
      $ALTROOT/boot/solaris/bootenv.rc
    # Also modify the system/keymap service
    Postboot "/usr/sbin/svccfg -s system/keymap:default"\
        "setprop keymap/layout = '$layout'"
    Postboot "/usr/sbin/svcadm refresh system/keymap:default"
    Postboot "/usr/sbin/svcadm restart system/keymap:default"
}

ApplyChanges() {
    SetRootPW
    [ -L $ALTROOT/etc/svc/profile/generic.xml ] || \
        logcmd ln -s generic_limited_net.xml \
        $ALTROOT/etc/svc/profile/generic.xml
    [ -L $ALTROOT/etc/svc/profile/name_service.xml ] || \
        logcmd ln -s ns_dns.xml $ALTROOT/etc/svc/profile/name_service.xml

    # Extras from interactive ISO/USB install...
    # arg1 == hostname
    [ -n "$1" ] && SetHostname $1

    # arg2 == timezone
    [ -n "$2" ] && SetTimezone $2

    # arg3 == Language
    [ -n "$3" ] && SetLang $3

    # arg4 == Keyboard layout
    [ -n "$4" ] && SetKeyboardLayout $4

    return 0
}

Postboot() {
    [ -f $ALTROOT/.initialboot ] || touch $ALTROOT/.initialboot
    log "Postboot - '$*'"
    echo "$*" >> $ALTROOT/.initialboot
}

Reboot() {
    # This is an awful hack... we already setup bootadm
    # and we've likely deleted enough of the userspace that this
    # can't run successfully... The easiest way to skip it is to
    # remove the binary
    logcmd rm -f /sbin/bootadm
    logcmd svccfg -s "system/boot-config:default" \
        setprop config/fastreboot_default=false
    logcmd svcadm refresh svc:/system/boot-config:default
    logcmd reboot
}

RunInstall(){
    FetchConfig || bomb "Could not fetch kayak config for target"
    # Set RPOOL if it wasn't done so already. We need it set.
    RPOOL=${RPOOL:-rpool}
    . $ICFILE
    Postboot 'exit $SMF_EXIT_OK'
    ApplyChanges || bomb "Could not apply all configuration changes"
    MakeBootable $RPOOL || bomb "Could not make new BE bootable"
    log "Installation complete"
    return 0
}

# Vim hints
# vim:ts=4:sw=4:et:fdm=marker
