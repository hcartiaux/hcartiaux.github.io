---
title: "Benchmarking NVMe-based storage with fio, bench-fio and fio-plot"
date: 2024-11-01
draft: false
tags: [sysadmin, linux, storage, benchmark]
toc: true
---

This post describes the usage of [`fio`](https://github.com/axboe/fio), [`bench-fio`](https://github.com/louwrentius/fio-plot/tree/master/bench_fio) and [`fio-plot`](https://github.com/louwrentius/fio-plot), to conduct a benchmark campaign and produce nice graphs. The tested system is a Dell R760 with 2 PERC 12 cards and 12 NVMe drives. The objective was to evaluate the impact of using hardware RAID on NVMe drives.

<!--more-->

## System description

System configuration:

* Dell PowerEdge R760
* 2x Intel Xeon Gold 6526Y, 16C/32T\@2.8 GHz
* 16x DIMM DDR5 16GB 5600MT/s (Hynix HMCG78AGBRA190N)
* BOSS-N1 card, with 2x NVMe M.2 480 Go (RAID 1)
* 2x Perc 12 (H965i, PCIe 4 16x/32GB/s)
  * 12x Dell NVMe ISE PS1030 MU U.2 3.2TB (Hynix HFS3T2GEJVX171N), balanced on both PERC cards
* Mellanox ConnectX-6 DX - 2x100 GbE QSFP56
* Redundant power supplies 1100W (1+1)

For the sake of reproducibility, the system use these firmwares versions:

| Firmware    | Version       |
|-------------|---------------|
| Bios        | 2.2.8         |
| iDDRAC      | 7.10.50.10    |
| H965i       | 8.8.0.0.18-26 |
| System CPLD | 1.2.1         |

The system is installed under Debian 12 (kernel `6.1.112-1`) and uses the kernel module `mpi3mr` (version 8.8.3.0.0) [provided by Dell](https://www.dell.com/support/home/fr-fr/drivers/driversdetails?driverid=33n4y&oscode=rhel9&productcode=poweredge-r760%7Cthe).
The archive for RHEL contains a [`DKMS`](https://wiki.debian.org/KernelDKMS) package for Ubuntu, which happens to be compatible with Debian 12.

```
$ apt update
$ apt upgrade
$ apt install dkms
$ mkdir PERC12 ; cd PERC12
$ tar xvf PERC12_RHEL9.4-8.8.3.0.0-1_Linux_Driver.tar.gz
$ tar xvf mpi3mr-release.tar
$ dpkg -i ubuntu/mpi3mr-8.8.3.0.0-1dkms.noarch.deb
# Unload the default module
$ rmmod mpi3mr
# Load the new module
$ modprobe mpi3mr
# Verify that the new module is loaded
$ modinfo mpi3mr
filename:       /lib/modules/6.1.0-26-amd64/updates/dkms/mpi3mr.ko
version:        8.8.3.0.0
license:        GPL
description:    MPI3 Storage Controller Device Driver
author:         Broadcom Inc. <mpi3mr-linuxdrv.pdl@broadcom.com>
```

## Raid configuration

The system has 2 PERC 12 cards, with 6 NVMes attached on each card.
I've benched 3 configuration:

1. one single NVMe drive in passthrough
2. all NVMe drives, in passthrough with LVM striping (no RAID)
3. one RAID 6 with 4+2 NVMe drives per card, plus LVM striping on the two RAID volumes

### Single NVMe drive configuration

Nothing special here, except the lazy init options which are disabled. 
This is important to ensure reproducibility, as lazy init means that the filesystem will be initialized by the kernel in background while being mounted.

```
mkfs.ext4 -E lazy_itable_init=0,lazy_journal_init=0 /dev/sda
```

### No RAID filesystem configuration (striping on 12 disks)

```
pvcreate /dev/sd{a,b,c,d,e,f,g,h,i,j,k,l}
vgcreate datavg /dev/sd{a,b,c,d,e,f,g,h,i,j,k,l}
lvcreate -y --type striped -L34.93t -i 12 -I 512k -n bench datavg
mkfs.ext4 /dev/datavg/bench
```

### Final filesystem configuration (dual RAID 6 4+2)

I've used `LVM` and `ext4`. Though I've noticed that `XFS` gives good results with default settings, `ext4` was a hard constraint on this system.

For the LVM and filesystem parameter, I've chosen these parameters through trial and error. It's relatively time consuming to try and benchmark combinations of parameters, and it is hard/confusing to cross the documentation at different levels (hardware raid manual and `LVM` and `ext4` man pages), these settings seems acceptable so I will not spend more time on this. 

#### LVM

1. Volume group creation

```
vgcreate --dataalignment 256K --physicalextentsize 4096K datavg /dev/sda /dev/sdb
```

2. Logical volume creation (stripe on 2 disks with a stripe size of 64k)

```
lvcreate --contiguous y --extents 100%FREE -i 2 -I 64k --name bench datavg
```

#### EXT4

```
mkfs.ext4  -E lazy_itable_init=0,lazy_journal_init=0,stride=16,stripe-width=128 -b 4096 /dev/datavg/bench
```

## Quick how-to


`bench-fio` automates benchmark campaigns using `fio`, and format the output for `fio-plot`.

```
$ apt install fio python3-pip python3.11-venv
$ python3 -m venv fio-plot
$ source fio-plot/bin/activate
$ pip3 install fio-plot
```

I've run two campaigns for each case:

* variations of `blocksize` (4k to 4m) with `iodepth 32|64/numjobs 64`

This is the input file:

```
[benchfio]
target = /mnt/fio-file
output = benchmark_nvmex1_bs
type = file
mode = read,write
size = 300G
iodepth = 64
numjobs = 64
block_size = 4k,8k,16k,32k,64k,128k,256k,512k,1m,2m,4m
direct = 1
engine = libaio
precondition = False
precondition_repeat = False
extra_opts = norandommap=1,refill_buffers=1
runtime = 45
destructive = True
```

* variations of `iodepth` (1 to 64) and `numjobs` (1 to 64) in `read` (sequential read operations), `write` (sequential write operations), `randread` (random read operations), `randwrite` (random write operations) for different block sizes (at first `4k` to maximize iops, `4m` to maximize bandwidth). For the last run, block sizes 64k/512k/1m seemed to be a better compromise.

```
[benchfio]
target = /mnt/fio-file
output = benchmark_nvmex1
type = file
mode = read,write
size = 300G
iodepth = 1,2,4,8,16,32,64
numjobs = 1,2,4,8,16,32,64
block_size = 4k,4m
direct = 1
engine = libaio
precondition = False
precondition_repeat = False
extra_opts = norandommap=1,refill_buffers=1
runtime = 45
destructive = True
```

* A campaign is started with the command `bench-fio <input file>.io` and it gives an output similar to this

```
                                    Bench-fio
  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
  ┃ Setting                        ┃ value                                     ┃
  ┡━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
  │ Estimated Duration             │ 0:44:00                                   │
  │ Number of benchmarks           │ 44                                        │
  │ Test target(s)                 │ /mnt/fio-file                             │
  │ Target type                    │ file                                      │
  │ I/O Engine                     │ libaio                                    │
  │ Test mode (read/write)         │ read write randread randwrite             │
  │ Specified test data size       │ 300G                                      │
  │ Block size                     │ 4k 8k 16k 32k 64k 128k 256k 512k 1m 2m 4m │
  │ IOdepth to be tested           │ 32                                        │
  │ NumJobs to be tested           │ 64                                        │
  │ Time duration per test (s)     │ 60                                        │
  │ Benchmark loops                │ 1                                         │
  │ Direct I/O                     │ 1                                         │
  │ Output folder                  │ run_2/benchmark_nvme2xraid6_bs            │
  │ Extra custom options           │ norandommap=1 refill_buffers=1            │
  │ Log interval of perf data (ms) │ 1000                                      │
  │ Invalidate buffer cache        │ 1                                         │
  │ Allow destructive writes       │ True                                      │
  │ Check remote timeout (s)       │ 2                                         │
  └────────────────────────────────┴───────────────────────────────────────────┘
  /mnt/fio-file ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ 100% 0:00:00
  　
                               Bench-fio
  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
  ┃ Setting                        ┃ value                          ┃
  ┡━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
  │ Estimated Duration             │ 9:48:00                        │
  │ Number of benchmarks           │ 588                            │
  │ Test target(s)                 │ /mnt/fio-file                  │
  │ Target type                    │ file                           │
  │ I/O Engine                     │ libaio                         │
  │ Test mode (read/write)         │ read write randread randwrite  │
  │ Specified test data size       │ 300G                           │
  │ Block size                     │ 64k 512k 1m                    │
  │ IOdepth to be tested           │ 1 2 4 8 16 32 64               │
  │ NumJobs to be tested           │ 1 2 4 8 16 32 64               │
  │ Time duration per test (s)     │ 60                             │
  │ Benchmark loops                │ 1                              │
  │ Direct I/O                     │ 1                              │
  │ Output folder                  │ run_2/benchmark_nvme2xraid6    │
  │ Extra custom options           │ norandommap=1 refill_buffers=1 │
  │ Log interval of perf data (ms) │ 1000                           │
  │ Invalidate buffer cache        │ 1                              │
  │ Allow destructive writes       │ True                           │
  │ Check remote timeout (s)       │ 2                              │
  └────────────────────────────────┴────────────────────────────────┘
  /mnt/fio-file ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ 100% 0:00:00
```

## Case #1 - Benchmark 1x NVMe

Generation commands for blocksize variations plots:


```
# IOPS/time (read)
fio-plot -i run_1/benchmark_nvmex1_bs/fio-file/{4k,8k,16k,32k,64k,128k,256k,512k,1m,2m,4m} -T "Dell R760 / Dual PERC12 / 1xNVME 3.5TB / mpi3mr 8.8.3.0.0" -g -r read -t iops -d 64 -n 64 --truncate-xaxis 40 --disable-fio-version -o "png/r760_nvmex1_8.8.3.0.0_read_iops.png"
# Bandwidth/time (read)
fio-plot -i run_1/benchmark_nvmex1_bs/fio-file/{4k,8k,16k,32k,64k,128k,256k,512k,1m,2m,4m} -T "Dell R760 / Dual PERC12 / 1xNVME 3.5TB / mpi3mr 8.8.3.0.0" -g -r read -t bw   -d 64 -n 64 --truncate-xaxis 40 --disable-fio-version -o "png/r760_nvmex1_8.8.3.0.0_read_bw.png"
# Latency/time (read)
fio-plot -i run_1/benchmark_nvmex1_bs/fio-file/{4k,8k,16k,32k,64k,128k,256k,512k,1m,2m,4m} -T "Dell R760 / Dual PERC12 / 1xNVME 3.5TB / mpi3mr 8.8.3.0.0" -g -r read -t lat  -d 64 -n 64 --truncate-xaxis 40 --disable-fio-version -o "png/r760_nvmex1_8.8.3.0.0_read_lat.png"
# IOPS/time (write)
fio-plot -i run_1/benchmark_nvmex1_bs/fio-file/{4k,8k,16k,32k,64k,128k,256k,512k,1m,2m,4m} -T "Dell R760 / Dual PERC12 / 1xNVME 3.5TB / mpi3mr 8.8.3.0.0" -g -r write -t iops -d 64 -n 64 --truncate-xaxis 40 --disable-fio-version -o "png/r760_nvmex1_8.8.3.0.0_write_iops.png"
# Bandwidth/time (write)
fio-plot -i run_1/benchmark_nvmex1_bs/fio-file/{4k,8k,16k,32k,64k,128k,256k,512k,1m,2m,4m} -T "Dell R760 / Dual PERC12 / 1xNVME 3.5TB / mpi3mr 8.8.3.0.0" -g -r write -t bw   -d 64 -n 64 --truncate-xaxis 40 --disable-fio-version -o "png/r760_nvmex1_8.8.3.0.0_write_bw.png"
# Latency/time (write)
fio-plot -i run_1/benchmark_nvmex1_bs/fio-file/{4k,8k,16k,32k,64k,128k,256k,512k,1m,2m,4m} -T "Dell R760 / Dual PERC12 / 1xNVME 3.5TB / mpi3mr 8.8.3.0.0" -g -r write -t lat  -d 64 -n 64 --truncate-xaxis 40 --disable-fio-version -o "png/r760_nvmex1_8.8.3.0.0_write_lat.png"
```

[![Benchmarks of 1xNVMe drive](bench_nvmex1.png)](bench_nvmex1.png)

Generation commands for 3D plots:

```
fio-plot -i run_1/benchmark_nvmex1/fio-file/4k -T "Dell R760 / Dual PERC12 / 1xNVME 3.5TB / mpi3mr 8.8.3.0.0 / bs 4k" --disable-fio-version -L -r read  -t iops -o "png/3d_r760_nvmex1_8.8.3.0.0_bs4k_read_iops.png"
fio-plot -i run_1/benchmark_nvmex1/fio-file/4k -T "Dell R760 / Dual PERC12 / 1xNVME 3.5TB / mpi3mr 8.8.3.0.0 / bs 4k" --disable-fio-version -L -r write -t iops -o "png/3d_r760_nvmex1_8.8.3.0.0_bs4k_write_iops.png"
fio-plot -i run_1/benchmark_nvmex1/fio-file/4m -T "Dell R760 / Dual PERC12 / 1xNVME 3.5TB / mpi3mr 8.8.3.0.0 / bs 4m" --disable-fio-version -L -r read  -t iops -o "png/3d_r760_nvmex1_8.8.3.0.0_bs4m_read_iops.png"
fio-plot -i run_1/benchmark_nvmex1/fio-file/4m -T "Dell R760 / Dual PERC12 / 1xNVME 3.5TB / mpi3mr 8.8.3.0.0 / bs 4m" --disable-fio-version -L -r write -t iops -o "png/3d_r760_nvmex1_8.8.3.0.0_bs4m_write_iops.png"

fio-plot -i run_1/benchmark_nvmex1/fio-file/4k -T "Dell R760 / Dual PERC12 / 1xNVME 3.5TB / mpi3mr 8.8.3.0.0 / bs 4k" --disable-fio-version -L -r read  -t lat -o "png/3d_r760_nvmex1_8.8.3.0.0_bs4k_read_lat.png"
fio-plot -i run_1/benchmark_nvmex1/fio-file/4k -T "Dell R760 / Dual PERC12 / 1xNVME 3.5TB / mpi3mr 8.8.3.0.0 / bs 4k" --disable-fio-version -L -r write -t lat -o "png/3d_r760_nvmex1_8.8.3.0.0_bs4k_write_lat.png"
fio-plot -i run_1/benchmark_nvmex1/fio-file/4m -T "Dell R760 / Dual PERC12 / 1xNVME 3.5TB / mpi3mr 8.8.3.0.0 / bs 4m" --disable-fio-version -L -r read  -t lat -o "png/3d_r760_nvmex1_8.8.3.0.0_bs4m_read_lat.png"
fio-plot -i run_1/benchmark_nvmex1/fio-file/4m -T "Dell R760 / Dual PERC12 / 1xNVME 3.5TB / mpi3mr 8.8.3.0.0 / bs 4m" --disable-fio-version -L -r write -t lat -o "png/3d_r760_nvmex1_8.8.3.0.0_bs4m_write_lat.png"

fio-plot -i run_1/benchmark_nvmex1/fio-file/4k -T "Dell R760 / Dual PERC12 / 1xNVME 3.5TB / mpi3mr 8.8.3.0.0 / bs 4k" --disable-fio-version -L -r read  -t bw -o "png/3d_r760_nvmex1_8.8.3.0.0_bs4k_read_bw.png"
fio-plot -i run_1/benchmark_nvmex1/fio-file/4k -T "Dell R760 / Dual PERC12 / 1xNVME 3.5TB / mpi3mr 8.8.3.0.0 / bs 4k" --disable-fio-version -L -r write -t bw -o "png/3d_r760_nvmex1_8.8.3.0.0_bs4k_write_bw.png"
fio-plot -i run_1/benchmark_nvmex1/fio-file/4m -T "Dell R760 / Dual PERC12 / 1xNVME 3.5TB / mpi3mr 8.8.3.0.0 / bs 4m" --disable-fio-version -L -r read  -t bw -o "png/3d_r760_nvmex1_8.8.3.0.0_bs4m_read_bw.png"
fio-plot -i run_1/benchmark_nvmex1/fio-file/4m -T "Dell R760 / Dual PERC12 / 1xNVME 3.5TB / mpi3mr 8.8.3.0.0 / bs 4m" --disable-fio-version -L -r write -t bw -o "png/3d_r760_nvmex1_8.8.3.0.0_bs4m_write_bw.png"
```

Results:

|                     | Peformance value |
|---------------------|------------------|
| Max IOPS            | ~350k            |
| Max Read bandwidth  | 3.5GB/s          |
| Max Write bandwidth | 3.5GB/s          |

## Case #2 - Benchmark all 12x NVMEs without RAID (LVM striping)

[![Benchmarks of 12xNVMe drives](bench_nvmex12.png)](bench_nvmex12.png)

Remark: The PERC12 cards are connected to PCI-E Gen4 16x ports, with a bandwidth of 4GB/s per lane, a 16x port has a single direction bandwidth of 32GB/s.
So the PCI-E ports are not a bottleneck, which is a nice improvement compared to the R750s/PERC 11.

Results:

|                     | Peformance value |
|---------------------|------------------|
| Max IOPS            | ~3M              |
| Max Read bandwidth  | 40GB/s           |
| Max Write bandwidth | 40GB/s           
|

## Case #3 - Benchmark the final configuration (2x RAID6 4+2 + LVM striping)

* Blocksize variations

[![Benchmarks of 12xNVMe drives in 2 RAID6 4+2](bench_nvme2xraid6.png)](bench_nvme2xraid6.png)

* 3D Graphs queuedepth/numjobs/bandwidth - blocksize 1M

[![3D Graphs of 12xNVMe drives in 2 RAID6 4+2 / bs1M / bandwidth](bench_nvme2xraid6_bs1m_bw.png)](bench_nvme2xraid6_bs1m_bw.png)

* 3D Graphs queuedepth/numjobs/iops - blocksize 64k

[![3D Graphs of 12xNVMe drives in 2 RAID6 4+2 / bs64k / iops](bench_nvme2xraid6_bs64k_iops.png)](bench_nvme2xraid6_bs64k_iops.png)

* 3D Graphs queuedepth/numjobs/lat - blocksize 512k

[![3D Graphs of 12xNVMe drives in 2 RAID6 4+2 / bs512k / lat](bench_nvme2xraid6_bs512k_lat.png)](bench_nvme2xraid6_bs512k_lat.png)


Results:

|                     | Peformance value |
|---------------------|------------------|
| Max IOPS            | ~700k            |
| Max Read bandwidth  | 40GB/s           |
| Max Write bandwidth | 30GB/s           |

## Conclusions

I've not included all the generated graphs in the previous sections, only the most relevant ones:

* we see a strong impact of the raid controllers on the max IOPs which are capped around 700k
* the RAID hardware controllers impact all latency measurements. It's useless to use more than 64 threads, the latency explodes above that number
* the random and sequential patterns give similar performance, which is expected for flash storage
* the write performance is severely impacted, which is normal considering the parity data.

## External resource

* [Louwrentius - Benchmarking Storage With Fio and Generating Charts of the Results](https://louwrentius.com/benchmarking-storage-with-fio-and-generating-charts-of-the-results.html)
