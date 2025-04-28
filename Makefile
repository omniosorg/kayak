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

#
# Copyright 2017 OmniTI Computer Consulting, Inc.  All rights reserved.
# Copyright 2023 OmniOS Community Edition (OmniOSce) Association.
#

ifeq ($(shell zonename),global)
BUILDSEND=rpool/kayak_image
else
BUILDSEND::="$(shell zfs list -H -o name /)/kayak_image"
endif
BUILDSEND_MP=/kayak_image

VERSION?=$(shell awk '$$1 == "OmniOS" { print $$3 }' /etc/release)
DESTDIR::=$(BUILDSEND_MP)

PKGDIRS=build src/include src bin etc data lib installer sample
IMG_FILES=corner.png tail_bg_v1.png OmniOSce_logo_medium.png tail_bg_v2.png
PKGFILES=Makefile README.md

TFTP_FILES=\
	$(DESTDIR)/tftpboot/kayak/miniroot.gz \
	$(DESTDIR)/tftpboot/kayak/miniroot.gz.hash \
	$(DESTDIR)/tftpboot/boot/grub/menu.lst \
	$(DESTDIR)/tftpboot/boot/loader.conf.local \
	$(DESTDIR)/tftpboot/boot/loader.rc \
	$(DESTDIR)/tftpboot/boot/forth \
	$(DESTDIR)/tftpboot/boot/defaults \
	$(DESTDIR)/tftpboot/boot/platform/i86pc/kernel/amd64/unix \
	$(DESTDIR)/tftpboot/pxeboot \
	$(DESTDIR)/tftpboot/pxegrub

GZ_ZFS_STREAM=$(DESTDIR)/var/kayak/kayak/$(VERSION).zfs.xz
NGZ_ZFS_STREAM=$(DESTDIR)/var/kayak/kayak/$(VERSION).ngz.zfs.xz

$(DESTDIR)/tftpboot/boot/loader.conf.local:	etc/loader.conf.local
	sed -e 's/@VERSION@/$(VERSION)/' $< > $@

$(DESTDIR)/tftpboot/boot/grub/menu.lst:	sample/menu.lst.000000000000
	sed -e 's/@VERSION@/$(VERSION)/' $< > $@

# Files from proto

$(DESTDIR)/tftpboot/pxegrub:	$(BUILDSEND_MP)/miniroot/boot/grub/pxegrub
	cp -p $< $@

$(DESTDIR)/tftpboot/pxeboot:	$(BUILDSEND_MP)/miniroot/boot/pxeboot
	cp -p $< $@

$(DESTDIR)/tftpboot/boot/loader.rc:	$(BUILDSEND_MP)/miniroot/boot/loader.rc
	cp -p $< $@

$(DESTDIR)/tftpboot/boot/forth:	$(BUILDSEND_MP)/miniroot/boot/forth
	cp -rp $< $@

$(DESTDIR)/tftpboot/boot/defaults:	$(BUILDSEND_MP)/miniroot/boot/defaults
	cp -rp $< $@

$(DESTDIR)/tftpboot/boot/platform/i86pc/kernel/amd64/unix:	$(BUILDSEND_MP)/miniroot/platform/i86pc/kernel/amd64/unix
	cp -p $< $@

$(GZ_ZFS_STREAM):	$(BUILDSEND_MP)/kayak_$(VERSION).zfs.xz
	cp -p $< $@

$(NGZ_ZFS_STREAM):	$(BUILDSEND_MP)/kayak_$(VERSION).ngz.zfs.xz
	cp -p $< $@

$(DESTDIR)/tftpboot/kayak/miniroot.gz:	$(BUILDSEND_MP)/miniroot.gz
	cp -p $< $@

$(DESTDIR)/tftpboot/kayak/miniroot.gz.hash:	$(BUILDSEND_MP)/miniroot.gz
	digest -a sha1 $< > $@

######################################################################
# More involved targets - creation of miniroot.gz and zfs images

$(BUILDSEND_MP)/kayak_$(VERSION).zfs.xz:	build/zfs_send
	@banner "ZFS GZ IMG"
	@test -d "$(BUILDSEND_MP)" || (echo "$(BUILDSEND) missing" && false)
	./$< -d $(BUILDSEND) $(VERSION)

$(BUILDSEND_MP)/kayak_$(VERSION).ngz.zfs.xz:	build/zfs_send
	@banner "ZFS NGZ IMG"
	@test -d "$(BUILDSEND_MP)" || (echo "$(BUILDSEND) missing" && false)
	./$< -d $(BUILDSEND) -V nonglobal $(VERSION)

$(BUILDSEND_MP)/aarch64_$(VERSION).zfs.xz:	build/zfs_send
	@banner "AARCH64 IMG"
	@test -d "$(BUILDSEND_MP)" || (echo "$(BUILDSEND) missing" && false)
	./$< -d $(BUILDSEND) -a aarch64 $(VERSION)

$(BUILDSEND_MP)/miniroot.gz:	build/miniroot
	@banner "MINIROOT"
	if test -n "`zfs list -H -t snapshot $(BUILDSEND)/miniroot@fixup 2>/dev/null`"; then \
	  VERSION=$(VERSION) DEBUG=$(DEBUG) ./$< $(BUILDSEND) fixup ; \
	else \
	  VERSION=$(VERSION) DEBUG=$(DEBUG) ./$< $(BUILDSEND) begin ; \
	fi

tftp-dirs:
	mkdir -p $(DESTDIR)/tftpboot/boot/grub
	mkdir -p $(DESTDIR)/tftpboot/boot/platform/i86pc/kernel/amd64
	mkdir -p $(DESTDIR)/tftpboot/kayak

server-dirs:
	mkdir -p $(DESTDIR)/var/kayak/kayak
	mkdir -p $(DESTDIR)/var/kayak/css
	mkdir -p $(DESTDIR)/var/kayak/img
	mkdir -p $(DESTDIR)/usr/share/kayak
	mkdir -p $(DESTDIR)/var/kayak/log
	mkdir -p $(DESTDIR)/var/svc/manifest/network
	mkdir -p $(DESTDIR)/var/svc/method

# Rebuilding the anonymous dtrace configuration file requires root in a
# zone with dtrace permissions. Provide no dependencies and it won't be
# rebuilt automatically.
# This is only used in debug mode to build a list of all files
# accessed in order to build the miniroot exclusion list. These days we
# just tend to add files by hand as required.
etc/anon.dtrace.conf:
	dtrace -A -q -s etc/anon.d -o $@.tmp
	cat /kernel/drv/dtrace.conf $@.tmp > $@
	rm $@.tmp

zfscreate:
	@banner $@
	zfs list -H -o name $(BUILDSEND) 2>/dev/null || \
	    zfs create -o mountpoint=$(BUILDSEND_MP) $(BUILDSEND)

zfsdestroy:
	@banner $@
	-zfs list -H -o name $(BUILDSEND) >/dev/null 2>&1 && \
	    zfs destroy -r $(BUILDSEND)

######################################################################
# Raspberry Pi components

RPIGITHUB=https://github.com/raspberrypi
RPIFWVER=1.20241126
download-rpi-firmware: bin/firmware-$(RPIFWVER)
bin/firmware-$(RPIFWVER):
	curl -fLo bin/firmware-$(RPIFWVER).tar.gz \
	    $(RPIGITHUB)/firmware/archive/refs/tags/$(RPIFWVER).tar.gz
	tar xf bin/firmware-$(RPIFWVER).tar.gz \
	    firmware-$(RPIFWVER)/boot -C bin
	rm -f bin/firmware-$(RPIFWVER).tar.gz
	ln -sf firmware-$(RPIFWVER) bin/rpi-firmware

bin/u-boot.rpi_4_defconfig bin/u-boot.rpi_arm64_defconfig: build/u-boot
	./build/u-boot

bin/bl31.bin: build/arm-trusted-fw
	./build/arm-trusted-fw

bin/barn:	src/barn.c
	gcc -m64 -o $@ $< -lnvpair

QEMU_BINS= bin/u-boot.qemu_arm64_defconfig
RPI_BINS= bin/firmware-$(RPIFWVER) \
	  bin/bl31.bin \
	  bin/u-boot.rpi_4_defconfig bin/u-boot.rpi_arm64_defconfig \
	  bin/barn
rpi-bins: $(RPI_BINS)

######################################################################
# Binaries to build from source

BINS=bin/takeover-console bin/ipcalc bin/dialog bin/passutil bin/mount_media \
	 etc/kbd.list bin/zpool_patch

bin/takeover-console:	src/takeover-console.c
	gcc -m32 -o $@ $<

bin/passutil:	src/passutil.c
	gcc -m32 -o $@ $<

bin/mount_media:	src/mount_media.c
	gcc -m32 -std=gnu99 -o $@ $< -ldevinfo

bin/zpool_patch:	src/zpool_patch.c
	gcc -m64 -g -Wall -Wunused -g -Isrc/include -o $@ $< -lnvpair

bin/ipcalc:	build/ipcalc
	./build/ipcalc

bin/dialog:	build/dialog
	./build/dialog

# Not a binary but a data file generated from key tables
etc/kbd.list: /usr/share/lib/keytables/type_6/kbd_layouts
	grep = /usr/share/lib/keytables/type_6/kbd_layouts | cut -d= -f1 \
		> etc/kbd.list

bins: $(BINS)

clean:
	-rm -f $(BINS)
	-rm -rf $(RPI_BINS) $(QEMU_BINS)
	-rm -rf VMDK-stream-converter-0.2

######################################################################
# Install targets (see README.md)

miniroot:	install-tftp
install-tftp:	zfscreate tftp-dirs $(TFTP_FILES)

zfs:		install-web
install-web:	zfscreate server-dirs $(GZ_ZFS_STREAM)

check-mkisofs:
	-@test -x `which mkisofs` || echo "No 'mkisofs' command found."
	@test -x `which mkisofs`

build-iso:
	@banner .ISO
	BUILDSEND_MP=$(BUILDSEND_MP) VERSION=$(VERSION) ./build/iso

build-usb:
	@banner .USB-DD
	./build/usb $(BUILDSEND_MP)/$(VERSION).iso \
	    $(BUILDSEND_MP)/$(VERSION).usb-dd

build-bhyve: bins zfs
	@banner .BHYVE
	BUILDSEND_MP=$(BUILDSEND_MP) ./build/bhyve

build-cloud: bins zfs
	@banner .CLOUD
	BUILDSEND_MP=$(BUILDSEND_MP) ./build/cloud

build-braich: bins zfscreate zfs_aarch64 rpi-bins
	@banner .BRAICH
	BUILDSEND_MP=$(BUILDSEND_MP) ./build/braich

install-iso:	check-mkisofs bins install-tftp install-web build-iso
install-usb:	install-iso build-usb
all:		install-usb $(NGZ_ZFS_STREAM) \
		build-bhyve build-cloud

zfs_gz:		$(BUILDSEND_MP)/kayak_$(VERSION).zfs.xz
zfs_ngz:	$(BUILDSEND_MP)/kayak_$(VERSION).ngz.zfs.xz
zfs_aarch64:	$(BUILDSEND_MP)/aarch64_$(VERSION).zfs.xz

# Used by omnios-build/kayak/ to create the kayak package

install-package:	bins tftp-dirs server-dirs
	for dir in $(PKGDIRS); do \
		mkdir -p $(DESTDIR)/usr/share/kayak/$$dir; \
		cp $$dir/* $(DESTDIR)/usr/share/kayak/$$dir/; \
	done
	for file in $(PKGFILES); do \
		cp $$file $(DESTDIR)/usr/share/kayak/$$file; \
	done
	for file in $(IMG_FILES); do \
		cp http/img/$$file $(DESTDIR)/var/kayak/img/$$file; \
	done
	\
	cp http/css/land.css $(DESTDIR)/var/kayak/css/land.css
	\
	cp smf/svc-kayak $(DESTDIR)/var/svc/method/svc-kayak
	chmod a+x $(DESTDIR)/var/svc/method/svc-kayak
	cp smf/kayak.xml $(DESTDIR)/var/svc/manifest/network/kayak.xml

.PHONY: all clean zfscreate zfsdestroy

