BUILDROOT_VERSION := 2026.08.1
BUILDROOT_DIR     := buildroot
DEFCONFIG         := configs/rv32i_mmu_defconfig
BUILDROOT_PATCHES := $(sort $(wildcard configs/buildroot-patches/*.patch))
BUILDROOT_STAMP   := $(BUILDROOT_DIR)/.patched

# Two images share one Buildroot clone and one set of patches. Each image gets
# its own output directory so both can coexist.
OUTPUT     := output-mmu
OUTPUT_MAX := output-mmu-max
CONFIG     := $(BUILDROOT_DIR)/$(OUTPUT)/.config
IMAGE      := $(BUILDROOT_DIR)/$(OUTPUT)/images/Image
IMAGE_MAX  := $(BUILDROOT_DIR)/$(OUTPUT_MAX)/images/Image
ROOTFS_EXT4     := $(BUILDROOT_DIR)/$(OUTPUT)/images/rootfs.ext4
ROOTFS_EXT4_MAX := $(BUILDROOT_DIR)/$(OUTPUT_MAX)/images/rootfs.ext4
DISK     := $(BUILDROOT_DIR)/$(OUTPUT)/images/disk.img
DISK_MAX := $(BUILDROOT_DIR)/$(OUTPUT_MAX)/images/disk.img
BOOT_DIR     := $(BUILDROOT_DIR)/$(OUTPUT)/images/boot
BOOT_DIR_MAX := $(BUILDROOT_DIR)/$(OUTPUT_MAX)/images/boot
GENIMAGE_CFG := configs/genimage-mmu.cfg

# The maximal images enable every extension the emulator implements and that
# Linux/ilp32 can use. Zbc is deliberately absent: the default emulator
# binary has Zbkc but not Zbc. Add zbc here (and rebuild the emulator with
# Zbc) if you want clmul as well.
ISA_EXTRA_MAX := zicntr_zicond_zihintntl_zihintpause_zimop_zca_zcb_zcmop_zba_zbb_zbkb_zbkc_zbkx_zbs

EMULATOR_DIR ?= ../RISC-V-emulator-Native
EMULATOR     ?= $(EMULATOR_DIR)/binaries/gcc/RV32I-linux-mmu
EMULATOR_MAX ?= $(EMULATOR_DIR)/binaries/gcc/RV32I-linux-mmu-max
EMULATOR_DISASM     ?= $(EMULATOR_DIR)/binaries/gcc/RV32I-linux-mmu-disasm
EMULATOR_MAX_DISASM ?= $(EMULATOR_DIR)/binaries/gcc/RV32I-linux-mmu-max-disasm

# The images boot through OpenSBI and U-Boot. Override OPENSBI or UBOOT
# to use another build.
OPENSBI ?= $(HOME)/Downloads/opensbi-1.9-rv-bin/share/opensbi/ilp32/generic/firmware/fw_jump.bin
UBOOT   ?= ../RISC-V-emulator-u-boot/build/u-boot.bin

# The DTS files live in the emulator repo, next to the hardware description
# they belong to. The Linux project only builds the DTBs.
DTS     ?= $(EMULATOR_DIR)/configs/linux-mmu.dts
DTS_MAX ?= $(EMULATOR_DIR)/configs/linux-mmu-max.dts
DTB     := linux-mmu.dtb
DTB_MAX := linux-mmu-max.dtb

# Generated maximal-image inputs. Keeping them generated avoids a second copy
# of the 1400-line kernel config and keeps the minimal config authoritative.
MAX_DEFCONFIG     := $(BUILDROOT_DIR)/$(OUTPUT_MAX)/rv32i_mmu_max_defconfig
MAX_KERNEL_CONFIG := $(BUILDROOT_DIR)/$(OUTPUT_MAX)/kernel_config_mmu_max

.PHONY: all build build-max buildroot \
        defconfig defconfig-max \
        disk disk-max \
        run run-max run-disasm run-max-disasm \
        clean clean-max distclean

all: build build-max disk

$(BUILDROOT_DIR)/Makefile:
	git clone --depth 1 --branch $(BUILDROOT_VERSION) \
		https://gitlab.com/buildroot.org/buildroot.git $(BUILDROOT_DIR)

$(BUILDROOT_STAMP): $(BUILDROOT_DIR)/Makefile $(BUILDROOT_PATCHES)
	@for p in $(BUILDROOT_PATCHES); do \
		if patch -d $(BUILDROOT_DIR) -p1 --dry-run < $$p >/dev/null 2>&1; then \
			echo "Applying Buildroot patch $$p"; \
			patch -d $(BUILDROOT_DIR) -p1 < $$p || exit 1; \
		elif patch -d $(BUILDROOT_DIR) -p1 -R --dry-run < $$p >/dev/null 2>&1; then \
			echo "Buildroot patch $$p already applied"; \
		else \
			echo "Buildroot patch $$p does not apply"; \
			exit 1; \
		fi; \
	done
	@touch $@

buildroot: $(BUILDROOT_STAMP)

$(CONFIG): $(BUILDROOT_STAMP) $(DEFCONFIG) \
		configs/kernel_config_mmu configs/busybox_config
	$(MAKE) -C $(BUILDROOT_DIR) O=$(OUTPUT) \
		BR2_DEFCONFIG=../$(DEFCONFIG) defconfig

$(MAX_KERNEL_CONFIG): configs/kernel_config_mmu | $(BUILDROOT_STAMP)
	@mkdir -p $(dir $@)
	sed -e 's|^# CONFIG_RISCV_ISA_C is not set|CONFIG_RISCV_ISA_C=y|' \
	    -e 's|^CONFIG_RISCV_ISA_ZICBOZ=y|# CONFIG_RISCV_ISA_ZICBOZ is not set|' \
	    -e 's|^CONFIG_RISCV_ISA_ZAWRS=y|# CONFIG_RISCV_ISA_ZAWRS is not set|' \
	    -e 's|^CONFIG_RISCV_ISA_ZACAS=y|# CONFIG_RISCV_ISA_ZACAS is not set|' \
	    -e 's|^CONFIG_RISCV_ISA_ZABHA=y|# CONFIG_RISCV_ISA_ZABHA is not set|' \
	    $< > $@

$(MAX_DEFCONFIG): $(DEFCONFIG) | $(BUILDROOT_STAMP)
	@mkdir -p $(dir $@)
	sed -e 's|^# BR2_RISCV_ISA_RVC is not set|BR2_RISCV_ISA_RVC=y|' \
	    -e 's|^BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE=.*|BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE="$(OUTPUT_MAX)/kernel_config_mmu_max"|' \
	    -e 's|^BR2_TARGET_GENERIC_HOSTNAME=.*|BR2_TARGET_GENERIC_HOSTNAME="rv32i-linux-mmu-max"|' \
	    -e 's|^BR2_TARGET_GENERIC_ISSUE=.*|BR2_TARGET_GENERIC_ISSUE="Welcome to rv32i-linux-mmu-max"|' \
	    $< > $@
	@printf '%s\n' 'BR2_RISCV_ISA_EXTRA="$(ISA_EXTRA_MAX)"' >> $@

$(BUILDROOT_DIR)/$(OUTPUT_MAX)/.config: $(BUILDROOT_STAMP) $(MAX_DEFCONFIG) \
		$(MAX_KERNEL_CONFIG) configs/busybox_config
	$(MAKE) -C $(BUILDROOT_DIR) O=$(OUTPUT_MAX) \
		BR2_DEFCONFIG=$(OUTPUT_MAX)/rv32i_mmu_max_defconfig defconfig

defconfig: $(CONFIG)
defconfig-max: $(BUILDROOT_DIR)/$(OUTPUT_MAX)/.config

build: $(CONFIG)
	$(MAKE) -C $(BUILDROOT_DIR) O=$(OUTPUT)

build-max: $(BUILDROOT_DIR)/$(OUTPUT_MAX)/.config
	$(MAKE) -C $(BUILDROOT_DIR) O=$(OUTPUT_MAX)

$(ROOTFS_EXT4): build
	@test -f $@ || { echo "Error: $@ was not produced by Buildroot."; exit 1; }

$(ROOTFS_EXT4_MAX): build-max
	@test -f $@ || { echo "Error: $@ was not produced by Buildroot."; exit 1; }

$(BOOT_DIR): build $(DTB)
	mkdir -p $@
	cp $(IMAGE) $@/Image
	cp $(DTB) $@/linux.dtb

$(BOOT_DIR_MAX): build-max $(DTB_MAX)
	mkdir -p $@
	cp $(IMAGE_MAX) $@/Image
	cp $(DTB_MAX) $@/linux.dtb

$(DISK): $(ROOTFS_EXT4) $(BOOT_DIR) $(GENIMAGE_CFG)
	PATH=$(BUILDROOT_DIR)/$(OUTPUT)/host/bin:$$PATH \
	genimage --rootpath $(BOOT_DIR) \
		--tmppath $(BUILDROOT_DIR)/$(OUTPUT)/genimage.tmp \
		--inputpath $(BUILDROOT_DIR)/$(OUTPUT)/images \
		--outputpath $(BUILDROOT_DIR)/$(OUTPUT)/images \
		--config $(GENIMAGE_CFG)

$(DISK_MAX): $(ROOTFS_EXT4_MAX) $(BOOT_DIR_MAX) $(GENIMAGE_CFG)
	PATH=$(BUILDROOT_DIR)/$(OUTPUT_MAX)/host/bin:$$PATH \
	genimage --rootpath $(BOOT_DIR_MAX) \
		--tmppath $(BUILDROOT_DIR)/$(OUTPUT_MAX)/genimage.tmp \
		--inputpath $(BUILDROOT_DIR)/$(OUTPUT_MAX)/images \
		--outputpath $(BUILDROOT_DIR)/$(OUTPUT_MAX)/images \
		--config $(GENIMAGE_CFG)

disk: $(DISK)
disk-max: $(DISK_MAX)

$(DTB): $(DTS)
	dtc -I dts -O dtb -o $@ $<

$(DTB_MAX): $(DTS_MAX)
	dtc -I dts -O dtb -o $@ $<

run: build $(DTB) $(DISK)
	$(EMULATOR) -b 0x82200000,$(DTB) \
		-l 0x80000000,$(OPENSBI) -l 0x80400000,$(UBOOT) -D $(DISK)

run-max: build-max $(DTB_MAX) $(DISK_MAX)
	$(EMULATOR_MAX) -b 0x82200000,$(DTB_MAX) \
		-l 0x80000000,$(OPENSBI) -l 0x80400000,$(UBOOT) -D $(DISK_MAX)

run-disasm: build $(DTB) $(DISK)
	$(EMULATOR_DISASM) -b 0x82200000,$(DTB) \
		-l 0x80000000,$(OPENSBI) -l 0x80400000,$(UBOOT) -D $(DISK)

run-max-disasm: build-max $(DTB_MAX) $(DISK_MAX)
	$(EMULATOR_MAX_DISASM) -b 0x82200000,$(DTB_MAX) \
		-l 0x80000000,$(OPENSBI) -l 0x80400000,$(UBOOT) -D $(DISK_MAX)

clean: clean-max
	@if [ -d $(BUILDROOT_DIR)/$(OUTPUT) ]; then \
		$(MAKE) -C $(BUILDROOT_DIR) O=$(OUTPUT) clean; \
	fi

clean-max:
	@if [ -d $(BUILDROOT_DIR)/$(OUTPUT_MAX) ]; then \
		$(MAKE) -C $(BUILDROOT_DIR) O=$(OUTPUT_MAX) clean; \
	fi

distclean:
	rm -rf $(BUILDROOT_DIR) $(DTB) $(DTB_MAX) linux.dtb
