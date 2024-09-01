---
title: "Extend a partition on an OpenBSD system"
date: 2024-05-01
draft: false
tags: [openbsd, sysadmin]
---

This post is a method to extend the last partition of the disk layout (usually) to use all the available disk space on an OpenBSD system.

<!--more-->

## Extend the disklabel partition layout

1. Read the disk layout with disklabel

```shell-session
disklabel -h sd0
# /dev/rsd0c:
type: SCSI
disk: SCSI disk
label: Block Device
duid: caebcd6353c3b714
flags:
bytes/sector: 512
sectors/track: 63
tracks/cylinder: 255
sectors/cylinder: 16065
cylinders: 13054
total sectors: 209715200 # total bytes: 102400.0M
boundstart: 64
boundend: 41943040

16 partitions:
#                size           offset  fstype [fsize bsize   cpg]
  a:           150.0M               64  4.2BSD   2048 16384  2400 # /
  b:           256.0M           307264    swap                    # none
  c:        102400.0M                0  unused
  d:          1981.7M           831552  4.2BSD   2048 16384 12960 # /usr
  e:           833.1M          4890048  4.2BSD   2048 16384 12960 # /tmp
  f:          1238.8M          6596256  4.2BSD   2048 16384 12960 # /var
  g:           651.4M          9133344  4.2BSD   2048 16384 10339 # /usr/X11R6
  h:          1915.4M         10467424  4.2BSD   2048 16384 12960 # /usr/local
  i:          2226.3M         14390144  4.2BSD   2048 16384 12960 # /usr/src
  j:          5476.5M         18949536  4.2BSD   2048 16384 12960 # /usr/obj
  k:          5750.8M         30165504  4.2BSD   2048 16384 12960 # /home
```


2. We can resize the last partition (here `sd0k`, mounted on `/home`), the max size in sectors is equal to `total sectors` (209715200) - `offset` (30165504).

```shell-session
disklabel -e sd0
```

This command will open the vi text editor, edit the line for `/home`, change the size to the value calculated before, and save.

```shell-session
# /dev/rsd0c:
type: SCSI
disk: SCSI disk
label: Block Device
duid: caebcd6353c3b714
flags:
bytes/sector: 512
sectors/track: 63
tracks/cylinder: 255
sectors/cylinder: 16065
cylinders: 13054
total sectors: 209715200
boundstart: 64
boundend: 41943040

16 partitions:
#                size           offset  fstype [fsize bsize   cpg]
  a:           307200               64  4.2BSD   2048 16384  2400 # /
  b:           524288           307264    swap                    # none
  c:        209715200                0  unused
  d:          4058496           831552  4.2BSD   2048 16384 12960 # /usr
  e:          1706208          4890048  4.2BSD   2048 16384 12960 # /tmp
  f:          2537088          6596256  4.2BSD   2048 16384 12960 # /var
  g:          1334080          9133344  4.2BSD   2048 16384 10339 # /usr/X11R6
  h:          3922720         10467424  4.2BSD   2048 16384 12960 # /usr/local
  i:          4559392         14390144  4.2BSD   2048 16384 12960 # /usr/src
  j:         11215968         18949536  4.2BSD   2048 16384 12960 # /usr/obj
  k:         179549696        30165504  4.2BSD   2048 16384 12960 # /home

# Notes:
# Up to 16 partitions are valid, named from 'a' to 'p'.  Partition 'a' is
# your root filesystem, 'b' is your swap, and 'c' should cover your whole
# disk. Any other partition is free for any use.  'size' and 'offset' are
# in 512-byte blocks. fstype should be '4.2BSD', 'swap', or 'none' or some
# other values.  fsize/bsize/cpg should typically be '2048 16384 16' for a
# 4.2BSD filesystem (or '512 4096 16' except on alpha, sun4, ...)
```

3. After saving, the partition size is updated:


```shell-session
disklabel -h sd0
# /dev/rsd0c:
type: SCSI
disk: SCSI disk
label: Block Device
duid: caebcd6353c3b714
flags:
bytes/sector: 512
sectors/track: 63
tracks/cylinder: 255
sectors/cylinder: 16065
cylinders: 13054
total sectors: 209715200 # total bytes: 102400.0M
boundstart: 64
boundend: 41943040

16 partitions:
#                size           offset  fstype [fsize bsize   cpg]
  a:           150.0M               64  4.2BSD   2048 16384  2400 # /
  b:           256.0M           307264    swap                    # none
  c:        102400.0M                0  unused
  d:          1981.7M           831552  4.2BSD   2048 16384 12960 # /usr
  e:           833.1M          4890048  4.2BSD   2048 16384 12960 # /tmp
  f:          1238.8M          6596256  4.2BSD   2048 16384 12960 # /var
  g:           651.4M          9133344  4.2BSD   2048 16384 10339 # /usr/X11R6
  h:          1915.4M         10467424  4.2BSD   2048 16384 12960 # /usr/local
  i:          2226.3M         14390144  4.2BSD   2048 16384 12960 # /usr/src
  j:          5476.5M         18949536  4.2BSD   2048 16384 12960 # /usr/obj
  k:         87670.8M         30165504  4.2BSD   2048 16384 12960 # /home
```


## Resize the filesystem with `growfs`

```shell-session
growfs /dev/sd0k
We strongly recommend you to make a backup before growing the Filesystem

 Did you backup your data (Yes/No) ? Yes
new filesystem size is: 44887424 frags
Warning: 390656 sector(s) cannot be allocated.
growfs: 87480.0MB (179159040 sectors) block size 16384, fragment size 2048
        using 432 cylinder groups of 202.50MB, 12960 blks, 25920 inodes.
super-block backups (for fsck -b #) at:
 12027040, 12441760, 12856480, 13271200, 13685920, 14100640, 14515360, 14930080, 15344800, 15759520, 16174240, 16588960, 17003680, 17418400, 17833120,
 ...
 174597280, 175012000, 175426720, 175841440, 176256160, 176670880, 177085600, 177500320, 177915040, 178329760, 178744480
```

Check the filesystem and remount it

```shell-session
fsck_ffs -f /dev/sd0k
** /dev/rsd0k
** Last Mounted on /home
** Phase 1 - Check Blocks and Sizes
** Phase 2 - Check Pathnames
** Phase 3 - Check Connectivity
** Phase 4 - Check Reference Counts
** Phase 5 - Check Cyl groups
11 files, 11 used, 43383113 free (17 frags, 5422887 blocks, 0.0% fragmentation)

MARK FILE SYSTEM CLEAN? [Fyn?] y


***** FILE SYSTEM WAS MODIFIED *****
shell# mount /home
shell# df -h /home
Filesystem     Size    Used   Avail Capacity  Mounted on
/dev/sd0k     82.7G   22.0K   78.6G     1%    /home
```

