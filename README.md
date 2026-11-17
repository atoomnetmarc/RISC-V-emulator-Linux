# Description

Buildroot-based Linux images for the `rv32imac` Sv32 target, booted on
[RISC-V-emulator-Native](../RISC-V-emulator-Native) through OpenSBI and U-Boot.

Two images are built from one source tree: a minimal image for the lean
emulator and a maximal image that enables every extension the emulator
implements. Each image has its own kernel, root filesystem and GPT disk.

# Target

| Item   | Value                                                                                |
| :----- | :----------------------------------------------------------------------------------- |
| ISA    | min `rv32imac_zicsr_zifencei_zicntr` plus Sv32; max the full emulator ISA plus Sv32   |
| ABI    | `ilp32` (no F/D)                                                                     |
| RAM    | 64 MiB at `0x80000000`                                                               |
| UART   | 16550A at `0x10000000` for `earlycon`; virtio-console at `0x10002000`, `console=hvc0` |
| Net    | virtio-net at `0x10003000`, static IPv4 and IPv6 ULA                                 |
| CLINT  | `0x02000000`                                                                         |
| SYSCON | `0x00100000` (poweroff/reboot)                                                       |
| DTB    | loaded at runtime (`-b 0x82200000,linux-mmu.dtb` or `linux-mmu-max.dtb`)             |
| Rootfs | ext4 on a GPT disk image, attached with `-D` (`disk.img`); no initramfs              |

# Build

```sh
make buildroot      # clone Buildroot 2026.08.1
make                # both images and both disks
make build          # minimal Image and rootfs.ext4
make build-max      # maximal Image and rootfs.ext4
make disk           # minimal disk image
make disk-max       # maximal disk image
```

The build needs `dtc` and a host toolchain. Buildroot is cloned into
`buildroot/` and patched on demand; the directory is gitignored.

# Run

```sh
make run            # minimal image
make run-max        # maximal image
make run-disasm     # minimal image with the instruction tracer
make run-max-disasm # maximal image with the instruction tracer
```

`make run` and `make run-max` expand to the following emulator invocations.
Build the DTBs first with `make linux-mmu.dtb` and `make linux-mmu-max.dtb`.

```sh
# minimal: OpenSBI at 0x80000000, U-Boot at 0x80400000, Linux from the disk
../RISC-V-emulator-Native/binaries/gcc/RV32I-linux-mmu \
    -b 0x82200000,linux-mmu.dtb \
    -l 0x80000000,$HOME/Downloads/opensbi-1.9-rv-bin/share/opensbi/ilp32/generic/firmware/fw_jump.bin \
    -l 0x80400000,../RISC-V-emulator-u-boot/build/u-boot.bin \
    -D buildroot/output-mmu/images/disk.img

# maximal: the full emulator ISA, Sv32 and the SBI
../RISC-V-emulator-Native/binaries/gcc/RV32I-linux-mmu-max \
    -b 0x82200000,linux-mmu-max.dtb \
    -l 0x80000000,$HOME/Downloads/opensbi-1.9-rv-bin/share/opensbi/ilp32/generic/firmware/fw_jump.bin \
    -l 0x80400000,../RISC-V-emulator-u-boot/build/u-boot.bin \
    -D buildroot/output-mmu-max/images/disk.img
```

Override `OPENSBI`, `UBOOT`, `EMULATOR_DIR` or `DTS` on the `make` command
line to use other builds. Add `-m <instructions>` to stop after a fixed
instruction count, `-N <ifname>` to attach a TAP interface to virtio-net, or
`-v` for an instruction trace.

# Disk layout

The disk is a GPT image with a 32M ext4 boot partition at 1M and a 16M ext4
rootfs at 33M. The boot partition holds the `Image` and the DTB; U-Boot loads
them and starts the kernel. The kernel mounts the rootfs by `PARTUUID`.

- `configs/genimage-mmu.cfg` defines the layout.
- The `PARTUUID` is duplicated in the genimage config and in both DTS files in
  the emulator repo. Change it in all three places.
- The rootfs size is `BR2_TARGET_ROOTFS_EXT2_SIZE`; increase it if the rootfs
  grows.
- The initramfs is disabled; without `-D` the kernel cannot mount the root.

# Notes

- The kernel `Image` is loaded by U-Boot at `0x80600000`; OpenSBI runs in
  M-mode and provides the SBI.
- The DTB's `chosen/bootargs` is authoritative; `CONFIG_CMDLINE` is only a
  fallback.
- The emulator must implement full `M` (DIV/REM), not just `Zmmul`.
- The minimal image needs `RV32I`, `M`, `A`, `C`, `Zicsr`, `Zifencei`,
  `Zicntr` and `Sv32`. Build the lean emulator with:
  ```sh
  cd ../RISC-V-emulator-Native
  pio run -e RV32I-linux-mmu
  ```
- The maximal ISA string is `rv32imac_zicsr_zifencei_zicntr_zicond_zihintntl_zihintpause_zimop_zca_zcb_zcmop_zba_zbb_zbkb_zbkc_zbkx_zbs`.
  `Zbc` is omitted because the default emulator binary has `Zbkc` but not
  `Zbc`.
- The DTS files live in the emulator repo next to the hardware description;
  this project only builds the DTBs.

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
