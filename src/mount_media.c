/*
 * CDDL HEADER START
 *
 * The contents of this file are subject to the terms of the
 * Common Development and Distribution License (the "License").
 * You may not use this file except in compliance with the License.
 *
 * You can obtain a copy of the license at usr/src/OPENSOLARIS.LICENSE
 * or http://www.opensolaris.org/os/licensing.
 * See the License for the specific language governing permissions
 * and limitations under the License.
 *
 * When distributing Covered Code, include this CDDL HEADER in each
 * file and include the License file at usr/src/OPENSOLARIS.LICENSE.
 * If applicable, add the following below this CDDL HEADER, with the
 * fields enclosed by brackets "[]" replaced with your own identifying
 * information: Portions Copyright [yyyy] [name of copyright owner]
 *
 * CDDL HEADER END
 */

/*
 * Copyright (c) 2008, 2011, Oracle and/or its affiliates. All rights reserved.
 * Copyright 2022 OmniOS Community Edition (OmniOSce) Association.
 */

/*
 * The install boot_archive contains a minimal set of utilities under /usr and
 * devfs is not populated. The SMF service live-fs-root bootstraps the process
 * by locating the media device and mounting the compressed /usr and /opt
 * to provide a fully functioning system. This utility traverses the device
 * tree looking for devices that potentially contain the media image, mounts
 * each in turn and checks whether it contains the volume set id passed on
 * the comamnd line. An exit of 0 means we succeeded, non-zero means we failed.
 */

#include <err.h>
#include <fcntl.h>
#include <fts.h>
#include <libdevinfo.h>
#include <limits.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <sys/dkio.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/sunddi.h>
#include <sys/types.h>

#define	HSFS_OPTS	"ro"
#define	UFS_OPTS	"ro,nologging,noatime"
#define	PCFS_OPTS	"ro"

static bool mounted = false;
static bool verbose = false;
static bool debug = false;
static bool tryharder = false;

static int
check_volsetid(const char *volid)
{
	char buf[BUFSIZ];
	FILE *fp;

	/* Check volume set id against requested */
	if ((fp = fopen("/.cdrom/.volsetid", "r")) == NULL) {
		if (verbose)
			warn("open(/.cdrom/.volsetid)");
		return (-1);
	}

	if (fgets(buf, BUFSIZ, fp) == NULL) {
		fclose(fp);
		if (verbose)
			printf("Could not read volsetid\n");
		return (-1);
	}

	fclose(fp);

	char *cp = strchr(buf, '\n');
	if (cp != NULL)
		*cp = '\0';
	if (verbose)
		printf("        VOLSETID:[%s]\n", buf);

	return (strcmp(volid, buf));
}

/*
 * Mounts and tests supplied path to iso file for supplied volid
 * Returns 0 if volid found, -1 otherwise.
 */
static int
test_iso_file(const char *path, const char *volid)
{
	char opts[MAX_MNTOPT_STR];
	int ret = -1;

	if (debug)
		printf("    attempting HSFS mount\n");
	strcpy(opts, HSFS_OPTS);
	if (mount(path, "/.cdrom", MS_RDONLY | MS_OPTIONSTR,
	    "hsfs", NULL, 0, opts, sizeof (opts)) != 0) {
		return (ret);
	}

	/* Mounted, see if it's the image we're looking for, unmount if not */
	ret = check_volsetid(volid);
	if (ret != 0) {
		if (verbose)
			printf("    wrong VOLSETID, unmounting\n");
		(void) umount("/.cdrom");
	}

	return (ret);
}

/*
 * Attempt to mount the path as pcfs. Then walk the file tree and look for any
 * iso files. For every one found, mount it and check for volid and umount if
 * failed. Returns 0 if the right iso is found and -1 otherwise.
 */
static int
check_for_iso(const char *path, const char *volid)
{
	char opts[MAX_MNTOPT_STR];
	int ret = -1;

	if (debug)
		printf("    attempting PCFS mount\n");
	strcpy(opts, PCFS_OPTS);
	if (mount(path, "/.usbdrive", MS_RDONLY | MS_OPTIONSTR,
	    "pcfs", NULL, 0, opts, sizeof (opts)) != 0) {
		return (-1);
	}

	/* mount succeeded, look for iso files */
	if (verbose) {
		printf("    >>>>>>> Mounted %s\n", path);
		printf("    Scanning /.usbdrive for .iso files\n");
	}

	FTS *tree;
	FTSENT *f;
	char *pathtowalk[] = { "/.usbdrive", NULL };

	tree = fts_open(pathtowalk, FTS_LOGICAL | FTS_NOSTAT, NULL);
	if (tree == NULL) {
		if (verbose)
			warn("fts_open failed");
		(void) umount("/.usbdrive");
		return (-1);
	}

	while ((f = fts_read(tree)) != NULL) {
		if (f->fts_info != FTS_F)
			continue;

		if (debug)
			printf("    file: [%s]\n", f->fts_name);

		if (f->fts_namelen > 4 && strcasecmp(".iso",
		    f->fts_name + f->fts_namelen - 4) == 0) {
			if (verbose)
				printf("    iso found: %s\n", f->fts_name);

			ret = test_iso_file(f->fts_path, volid);
			if (ret == 0)
				break;
		}
	}

	if (fts_close(tree) < 0 && verbose)
		warn("error closing tree");

	if (ret != 0) {
		if (verbose)
			printf("Did not find a matching .iso file\n");
		(void) umount("/.usbdrive");
		/* if ret==0 we do not unmount the usbdrive mount */
	}

	return (ret);
}

static int
mount_image(const char *path, const char *volid)
{
	char opts[MAX_MNTOPT_STR];
	int ret = -1;
	char *fs;

	/*
	 * First try mounting it as hsfs; if that fails, try ufs; if
	 * that fails try check_for_iso()
	 */
	if (debug)
		printf("    attempting HSFS mount\n");
	strcpy(opts, HSFS_OPTS);
	if (mount(path, "/.cdrom", MS_RDONLY | MS_OPTIONSTR, "hsfs",
	    NULL, 0, opts, sizeof (opts)) == 0) {
		fs = "hsfs";
		goto mounted;
	}

	if (debug)
		printf("    attempting UFS mount\n");
	strcpy(opts, UFS_OPTS);
	if (mount(path, "/.cdrom", MS_OPTIONSTR, "ufs", NULL, 0,
	    opts, sizeof (opts)) == 0) {
		fs = "ufs";
		goto mounted;
	}

	if (check_for_iso(path, volid) == 0) {
		fs = "pcfs";
		goto mounted;
	}

	return (ret);

mounted:

	if (verbose)
		printf("    >>>>>>> Mounted %s (%s)\n", path, fs);

	/* Mounted, see if it's the image we're looking for, unmount if not */
	ret = check_volsetid(volid);
	if (ret != 0) {
		if (verbose)
			printf("    wrong VOLSETID, unmounting\n");
		(void) umount("/.cdrom");
	}

	return (ret);
}

/*
 * Callback function for di_walk_minor. For each node that appears to match
 * our criteria (a USB block device, or a CD), mount it and see if it
 * matches the volume set id passed on the command line. If so, we're done
 * and can terminate the walk. In all error cases, just continue walking the
 * tree.
 */
static int
mount_minor(di_node_t node, di_minor_t minor, void *arg)
{
	char mpath[PATH_MAX];
	char *volid = arg;
	char *cp;

	char *driver = di_driver_name(node);
	char *nodetype = di_minor_nodetype(minor);
	char *minorpath = di_devfs_minor_path(minor);
	int spectype = di_minor_spectype(minor);

	if (nodetype == NULL || minorpath == NULL || driver == NULL) {
		if (verbose)
			printf("failed reading attributes for %d\n", minor);
		return (DI_WALK_CONTINUE);
	}

	strcpy(mpath, "/devices");
	strlcat(mpath, minorpath, sizeof (mpath));

	if (verbose) {
		char type[20];

		switch (spectype) {
		case S_IFBLK:
			strcpy(type, "BLK");
			break;
		case S_IFCHR:
			strcpy(type, "CHR");
			break;
		default:
			snprintf(type, sizeof (type), "type=%d", spectype);
			break;
		}
		printf("Checking %s [%s/%s/%s]\n", minorpath,
		    driver, nodetype, type);
	}

	/* If it's a block device and claims to be USB, try mounting it */
	if (spectype == S_IFBLK) {
		int **prop;

		if (di_prop_lookup_ints(DDI_DEV_T_ANY, node,
		    "usb", prop) != -1) {
			if (verbose)
				printf("   block device with a USB property\n");
			goto mount;
		}
	}

	/* Node type is a CD. Try mounting it */
	if (strstr(nodetype, DDI_NT_CD) != NULL ||
	    strstr(nodetype, DDI_NT_CD_CHAN) != NULL) {
		if (verbose)
			printf("  nodetype CD/CD_CHAN\n");
		goto mount;
	}

	/* If node type is not marked, need to check device type via ioctls. */
	int fd = open(mpath, O_NDELAY | O_RDONLY);
	if (fd == -1) {
		if (debug)
			warn("open(%s)", mpath);
		goto end;
	}
	struct dk_cinfo dkinfo;
	int ret = ioctl(fd, DKIOCINFO, &dkinfo);
	(void) close(fd);
	if (ret != 0)
		goto end;
	if (verbose)
		printf("    DKC_TYPE %d\n", dkinfo.dki_ctype);
	if (dkinfo.dki_ctype == DKC_CDROM)
		goto mount;
	if (dkinfo.dki_ctype == DKC_DIRECT && strcmp(driver, "cmdk") == 0)
		goto mount;
	/* Try generic block devices too if we're trying harder */
	if (tryharder && dkinfo.dki_ctype == DKC_BLKDEV)
		goto mount;

	goto end;

mount:
	/* Remove raw suffix from path to get to block device for mount */
	cp = strstr(mpath, ",raw");
	if (cp != NULL)
		*cp = '\0';
	if (mount_image(mpath, volid) == 0) {
		printf("Found %s media at %s\n", volid, mpath);
		mounted = true;
	}

end:
	di_devfs_path_free(minorpath);
	return (mounted ? DI_WALK_TERMINATE : DI_WALK_CONTINUE);
}

int
main(int argc, char **argv)
{
	di_node_t root_node;
	char *volid;

	while (argc > 1 && *argv[1] == '-') {
		if (strcmp(argv[1], "-v") == 0) {
			verbose = true;
		} else if (strcmp(argv[1], "-d") == 0) {
			verbose = debug = true;
		} else {
			errx(1, "unknown option %s", argv[1]);
		}
		argc--, argv++;
	}

	if (argc == 1) {
		fprintf(stderr, "Usage: mount_media [-v] [-d] <volsetid>\n");
		return (1);
	}

	volid = argv[1];

	/* Initialize libdevinfo and walk the tree */
	if ((root_node = di_init("/", DINFOCPYALL)) == DI_NODE_NIL)
		err(1, "Failed to initialise root node");
	(void) di_walk_minor(root_node, DDI_NT_BLOCK, 0, volid, mount_minor);
	if (!mounted) {
		/*
		 * If we failed to find a device, loop through again and try
		 * harder. This generally means we'll attempt to mount every
		 * block device we find.
		 */
		tryharder = true;
		(void) di_walk_minor(root_node, DDI_NT_BLOCK, 0, volid,
		    mount_minor);
	}
	di_fini(root_node);

	return (mounted ? 0 : 1);
}
