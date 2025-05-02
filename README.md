Using Kayak
===========

Building
--------

 * Set `PKGURL` to be the source of the OmniOS bits we wish to install with
   kayak, in case it's not the default "omnios" publisher for whatever release
   branch you have checked out.

 * `zfs create rpool/kayak_image`
 * `gmake [PREBUILT_ILLUMOS=<path>] BUILDSEND=rpool/kayak_image <target>`

`BUILDSEND` must be specified.

`PREBUILT_ILLUMOS` should point to an already-built illumos-omnios of the
version you wish to construct an installer.  It is optional, but the build
will warn you if you do not specify it. The build uses `svccfg-native` if
possible to manipulate SMF on target images without conversing with the host
machine's SMF services.

`<target>` must be specified.

`install-web`:
	Builds the `<VERSION>.zfs.xz` file, which is what Kayak uses
	for any install it does. Independent target.

`install-tftp`:
	Builds the miniroot.gz file, which is what PXE Kayak feeds to
	Loader to boot itself on a PXE boot. Independent target.

`install-iso`:
	Builds both `install-{web,tftp}` and then proceeds to construct
	`<VERSION>.iso` using components from both.

`install-usb`:
	Builds `install-iso`, and then proceed to construct `<VERSION>.usb-dd`
	based on the ISO image.

Operation
---------

DHCP server:
 * your server should be set to PXE boot
 * the DHCP server must return and IP, a nextserver and a bootfile
 * the boot file should be the file `/boot/pxeboot` from an existing OmniOS system

TFTP server:
 * place `loader.conf.local` in `/tftpboot/boot`
 * `/boot/pxeboot` should be placed in `/tftpboot/`
 * `/platform/i86pc/kernel/amd64/unix` should be placed in `/tftpboot/omnios/kayak/`
 * the `miniroot.gz` file should be placed in `/tftpboot/omnios/kayak/`

HTTP server:
 * The system install images should be placed an accessible URL
 * The target system kayak config should be placed at a URL path with the filename `<macaddr_just_hex_caps>`

