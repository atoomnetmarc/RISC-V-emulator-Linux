# Disk root design

## Goal

`make` and `make disk` produce one bootable GPT/ext4 disk image per image
variant (`output-mmu/images/disk.img` and `output-mmu-max/images/disk.img`).
The emulator attaches the disk with `-D`; U-Boot loads the kernel and the DTB
from `/boot` on the single partition and the kernel mounts that partition as
its root filesystem. The kernel has no initramfs.

## Status

Implemented and validated. Both the minimal and maximal images boot from their
own GPT/ext4 disk: `vda1` holds `/boot` and the root, the kernel pivots into the
new rootfs, and the login shell appears.

## Decisions

| #   | Decision                                                                                               | Rationale                                                                                                                            |
| --- | ------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------ |
| 1   | The root filesystem is a disk partition; the kernel has no initramfs                                   | One boot path, smaller `Image`, no dead ramfs payload.                                                                               |
| 2   | Both the minimal and maximal images get their own disk                                                 | The programs on each disk use the respective ISA extensions; keeps the two-image design symmetric.                                   |
| 3   | Top-level `make disk` target using Buildroot's host-genimage                                           | `make disk` is a real standalone target, the GPT is reproducible, and ownership comes from Buildroot's fakeroot-built `rootfs.ext4`. |
| 4   | One 1GiB ext4 partition for both variants                                                              | Room for glibc, Python 3, `mc`, `nano` and `links`; one filesystem to manage.                                                        |
| 5   | The partition starts at 1M and is partition 1                                                          | U-Boot keeps `ext4load virtio 0:1` for `/boot/Image` and `/boot/linux.dtb`.                                                         |
| 6   | Fixed GPT `PARTUUID` as the root reference                                                             | GPT-native and robust to device naming; the partition type UUID is predefined, the PARTUUID is a chosen constant.                    |
| 7   | One fixed PARTUUID constant duplicated in `configs/genimage-mmu.cfg` and both DTS files                | Stable constant, two-line duplication, and no DTS templating or moving the DTS out of the emulator repo.                             |
| 8   | A post-build script copies the kernel and DTB into `/boot` in the rootfs                               | genimage builds the ext4 from Buildroot's `rootfs.ext4`, so the boot files must be in `$(TARGET_DIR)/boot` before the ext2 image step. |

## Disk layout

```
sector 0        protective MBR
sector 1        GPT header
sector 2..33    GPT partition entries
1 MiB           partition 1: Linux filesystem data (0FC63DAF-8483-4772-8E79-3D69D8477DE4)
                ext4, 1G, label "rootfs", holds /boot/Image, /boot/linux.dtb and the root
end             backup GPT
```

The partition unique GUID (`partition-uuid` in genimage) is the value used by
`root=PARTUUID=...`. It is not a predefined type GUID; it is a fixed constant
chosen for this project and duplicated in the DTS files.

## Implementation outline

1. `configs/rv32i_mmu_defconfig`
   - `BR2_TARGET_ROOTFS_EXT2=y`, `BR2_TARGET_ROOTFS_EXT2_4=y`,
     `BR2_TARGET_ROOTFS_EXT2_SIZE="1G"`,
     `BR2_TARGET_ROOTFS_EXT2_LABEL="rootfs"`,
     `BR2_PACKAGE_HOST_GENIMAGE=y`.
   - `BR2_ROOTFS_POST_BUILD_SCRIPT` points at `configs/post-build.sh`.
   - No `BR2_TARGET_ROOTFS_CPIO` and no `BR2_TARGET_ROOTFS_INITRAMFS`.
2. `configs/kernel_config_mmu`
   - No `CONFIG_INITRAMFS_SOURCE`.
   - `CONFIG_BLK_DEV_INITRD` is disabled.
   - `CONFIG_EFI_PARTITION=y` and `CONFIG_MSDOS_PARTITION=y`.
3. `configs/genimage-mmu.cfg`
   - GPT, one 1G ext4 partition at 1M with a fixed `partition-uuid`.
4. `configs/post-build.sh`
   - Copies `Image` and `linux.dtb` from `$(BINARIES_DIR)` into `$(TARGET_DIR)/boot`.
5. `Makefile`
   - `DISK := $(CACHE)/out-mmu/images/disk.img`,
     `DISK_MAX := $(CACHE)/out-mmu-max/images/disk.img`.
   - `BOOT_DTB` copies the variant DTB into `$(OUT)/images/linux.dtb` before
     the Buildroot build.
   - `disk`/`disk-max` depend on `rootfs.ext4`, the genimage config and the DTB
     copy, invoke genimage and copy the result into the gitignored `artifacts/`
     directory with `cp --sparse=always`.
   - `run`/`run-max` depend on the copied disk and pass `-D`.
6. Emulator DTS (`../RISC-V-emulator-Native/configs/linux-mmu.dts` and
   `linux-mmu-max.dts`)
   - `chosen/bootargs` is `root=PARTUUID=<fixed> rw rootfstype=ext4`.
7. `README.md`
   - The rootfs row, the disk layout, the build and run sections, and the notes.

## Validation

1. `make build` produces `$(CACHE)/out-mmu/images/rootfs.ext4` with
   `/boot/Image` and `/boot/linux.dtb`.
2. `make disk` produces `artifacts/disk.img`.
3. `fdisk -l artifacts/disk.img` shows a GPT with one 1G ext4 partition at 1M.
4. `make run` boots through OpenSBI and U-Boot and mounts the ext4 root.
5. Repeat for the maximal image with `make build-max`, `make disk-max` and
   `make run-max`.

## Risks

- The PARTUUID is duplicated in three places; a mismatch produces a
  non-booting image.
- The 1G ext4 size is fixed; if the target rootfs grows past it, the Buildroot
  ext2 step fails with a clear "increase BR2_TARGET_ROOTFS_EXT2_SIZE" message.
- The boot files live in the writable root filesystem; deleting `/boot/Image`
  or `/boot/linux.dtb` breaks the next boot.
