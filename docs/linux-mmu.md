# Linux MMU target

The MMU image runs a real Linux kernel with paged virtual memory. The kernel runs in S-mode, OpenSBI provides the SBI, and U-Boot loads the kernel from the disk.

## Kernel configuration

The MMU image uses:

- `CONFIG_MMU=y`
- `CONFIG_RISCV_SBI=y`
- `CONFIG_RISCV_M_MODE=n`
- `CONFIG_SMP=n`
- `CONFIG_TMPFS=y`

The image keeps the ext4 disk root and the virtio devices. The libc is uClibc-ng. U-Boot loads the kernel `Image` at `0x80600000`; OpenSBI `fw_jump` is the firmware. The DTS supplies `riscv,isa-base` and `riscv,isa-extensions` for ISA detection; the legacy `riscv,isa` string stays for boot stages that use it.

## Linux constraints

`CONFIG_MMU` and `CONFIG_NOMMU` are the only modes. There is no plug-in MMU.

On RV32, `CONFIG_MMU` means Sv32. Sv39, Sv48 and Sv57 are RV64-only.

`CONFIG_RISCV_SBI` depends on `!RISCV_M_MODE` and defaults to y.

RV32 uses `pgtable-nopmd.h`; the PMD is folded, so Linux uses 4 KiB leaf PTEs and no 4 MiB superpages.

Linux sets A and D at PTE creation. `arch_has_hw_pte_young()` is true only with Svadu. With Svade, a PTE with A or D clear raises a page fault and Linux sets the bit in its fault handler.

Linux uses `sstatus.SUM` for user access and writes `scounteren` in `head.S`.

The kernel entry expects S-mode with `a0` set to the hart ID, `a1` set to the DTB and `satp` set to Bare.

## Boot chain

The emulator starts in M-mode at `0x80000000` and loads OpenSBI `fw_jump.bin` at `0x80000000`. OpenSBI jumps to U-Boot at `0x80400000`. U-Boot loads the Linux `Image` and the DTB from the boot partition on the virtio disk and starts the kernel with `booti`. The memory map, the disk layout and the U-Boot environment are in [the U-Boot design](../../RISC-V-emulator-u-boot/docs/design.md).

## Buildroot

The MMU image is a Buildroot product. The build, the disk and the run targets are in [the RISC-V-emulator-Linux README](../README.md).

## Run

The run command is in [the RISC-V-emulator-Linux README](../README.md). The emulator attaches the disk with `-D`, loads OpenSBI and U-Boot with `-l`, and loads the DTB with `-b`.
