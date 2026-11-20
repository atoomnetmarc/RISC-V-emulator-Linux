BUILDROOT_VERSION := 2026.08.1
XDG_CACHE_HOME   ?= $(HOME)/.cache
CACHE            := $(XDG_CACHE_HOME)/riscv-emulator
BUILDROOT_SRC    := $(CACHE)/buildroot-$(BUILDROOT_VERSION)
BUILDROOT_DL     := $(CACHE)/buildroot-dl
BUILDROOT_PATCHES := $(sort $(wildcard configs/buildroot-patches/*.patch))
BUILDROOT_STAMP  := $(CACHE)/buildroot-$(BUILDROOT_VERSION).patched
DEFCONFIG        := configs/rv32i_mmu_defconfig
EXTERNAL         := $(CURDIR)

# Two images share one Buildroot clone and one set of patches. Each image gets
# its own output directory in the cache so both can coexist.
OUT     := $(CACHE)/out-mmu
OUT_MAX := $(CACHE)/out-mmu-max
CONFIG     := $(OUT)/.config
IMAGE      := $(OUT)/images/Image
IMAGE_MAX  := $(OUT_MAX)/images/Image
ROOTFS_EXT4     := $(OUT)/images/rootfs.ext4
ROOTFS_EXT4_MAX := $(OUT_MAX)/images/rootfs.ext4
DISK     := $(OUT)/images/disk.img
DISK_MAX := $(OUT_MAX)/images/disk.img
BOOT_DIR     := $(OUT)/images/boot
BOOT_DIR_MAX := $(OUT_MAX)/images/boot
GENIMAGE_CFG := configs/genimage-mmu.cfg

# Only final images are copied back into the repository.
ARTIFACTS         := artifacts
DISK_ARTIFACT     := $(ARTIFACTS)/disk.img
DISK_MAX_ARTIFACT := $(ARTIFACTS)/disk-max.img
DTB     := $(ARTIFACTS)/linux-mmu.dtb
DTB_MAX := $(ARTIFACTS)/linux-mmu-max.dtb

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

# The images boot through OpenSBI and U-Boot. Both are built in their own
# repos; override OPENSBI, OPENSBI_MAX or UBOOT to use other builds.
OPENSBI     ?= ../RISC-V-emulator-opensbi/build-min/platform/generic/firmware/fw_jump.bin
OPENSBI_MAX ?= ../RISC-V-emulator-opensbi/build-max/platform/generic/firmware/fw_jump.bin
UBOOT       ?= ../RISC-V-emulator-u-boot/build/u-boot.bin

# The DTS files live in the emulator repo, next to the hardware description
# they belong to. The Linux project only builds the DTBs.
DTS     ?= $(EMULATOR_DIR)/configs/linux-mmu.dts
DTS_MAX ?= $(EMULATOR_DIR)/configs/linux-mmu-max.dts

# Generated maximal-image inputs. Keeping them generated avoids a second copy
# of the 1400-line kernel config and keeps the minimal config authoritative.
MAX_DEFCONFIG     := $(OUT_MAX)/rv32i_mmu_max_defconfig
MAX_KERNEL_CONFIG := $(OUT_MAX)/kernel_config_mmu_max

.PHONY: all build build-max buildroot \
        defconfig defconfig-max \
        disk disk-max artifacts \
        run run-max run-disasm run-max-disasm \
        clean clean-max distclean purge-cache

all: build build-max disk

$(BUILDROOT_SRC)/Makefile:
	mkdir -p $(CACHE)
	git clone --depth 1 --branch $(BUILDROOT_VERSION) \
		https://gitlab.com/buildroot.org/buildroot.git $(BUILDROOT_SRC)

$(BUILDROOT_STAMP): $(BUILDROOT_SRC)/Makefile $(BUILDROOT_PATCHES)
	@for p in $(BUILDROOT_PATCHES); do \
		if patch -d $(BUILDROOT_SRC) -p1 --dry-run < $$p >/dev/null 2>&1; then \
			echo "Applying Buildroot patch $$p"; \
			patch -d $(BUILDROOT_SRC) -p1 < $$p || exit 1; \
		elif patch -d $(BUILDROOT_SRC) -p1 -R --dry-run < $$p >/dev/null 2>&1; then \
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
	BR2_DL_DIR=$(BUILDROOT_DL) $(MAKE) -C $(BUILDROOT_SRC) O=$(OUT) \
		BR2_EXTERNAL=$(EXTERNAL) BR2_DEFCONFIG=$(CURDIR)/$(DEFCONFIG) defconfig

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
	    -e 's|^BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE=.*|BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE="$(OUT_MAX)/kernel_config_mmu_max"|' \
	    -e 's|^BR2_TARGET_GENERIC_HOSTNAME=.*|BR2_TARGET_GENERIC_HOSTNAME="rv32i-linux-mmu-max"|' \
	    -e 's|^BR2_TARGET_GENERIC_ISSUE=.*|BR2_TARGET_GENERIC_ISSUE="Welcome to rv32i-linux-mmu-max"|' \
	    $< > $@
	@printf '%s\n' 'BR2_RISCV_ISA_EXTRA="$(ISA_EXTRA_MAX)"' >> $@

$(OUT_MAX)/.config: $(BUILDROOT_STAMP) $(MAX_DEFCONFIG) \
		$(MAX_KERNEL_CONFIG) configs/busybox_config
	BR2_DL_DIR=$(BUILDROOT_DL) $(MAKE) -C $(BUILDROOT_SRC) O=$(OUT_MAX) \
		BR2_EXTERNAL=$(EXTERNAL) BR2_DEFCONFIG=$(MAX_DEFCONFIG) defconfig

defconfig: $(CONFIG)
defconfig-max: $(OUT_MAX)/.config

build: $(CONFIG)
	BR2_DL_DIR=$(BUILDROOT_DL) $(MAKE) -C $(BUILDROOT_SRC) O=$(OUT) BR2_EXTERNAL=$(EXTERNAL)

build-max: $(OUT_MAX)/.config
	BR2_DL_DIR=$(BUILDROOT_DL) $(MAKE) -C $(BUILDROOT_SRC) O=$(OUT_MAX) BR2_EXTERNAL=$(EXTERNAL)

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
	PATH=$(OUT)/host/bin:$$PATH \
	genimage --rootpath $(BOOT_DIR) \
		--tmppath $(OUT)/genimage.tmp \
		--inputpath $(OUT)/images \
		--outputpath $(OUT)/images \
		--config $(GENIMAGE_CFG)

$(DISK_MAX): $(ROOTFS_EXT4_MAX) $(BOOT_DIR_MAX) $(GENIMAGE_CFG)
	PATH=$(OUT_MAX)/host/bin:$$PATH \
	genimage --rootpath $(BOOT_DIR_MAX) \
		--tmppath $(OUT_MAX)/genimage.tmp \
		--inputpath $(OUT_MAX)/images \
		--outputpath $(OUT_MAX)/images \
		--config $(GENIMAGE_CFG)

$(ARTIFACTS)/.dir:
	mkdir -p $(ARTIFACTS)
	@touch $@

$(DISK_ARTIFACT): $(DISK) | $(ARTIFACTS)/.dir
	cp $< $@

$(DISK_MAX_ARTIFACT): $(DISK_MAX) | $(ARTIFACTS)/.dir
	cp $< $@

disk: $(DISK_ARTIFACT)
disk-max: $(DISK_MAX_ARTIFACT)
artifacts: $(DISK_ARTIFACT) $(DISK_MAX_ARTIFACT) $(DTB) $(DTB_MAX)

$(DTB): $(DTS) | $(ARTIFACTS)/.dir
	dtc -I dts -O dtb -o $@ $<

$(DTB_MAX): $(DTS_MAX) | $(ARTIFACTS)/.dir
	dtc -I dts -O dtb -o $@ $<

run: build $(DTB) $(DISK_ARTIFACT)
	$(EMULATOR) -b 0x82200000,$(DTB) \
		-l 0x80000000,$(OPENSBI) -l 0x80400000,$(UBOOT) -D $(DISK_ARTIFACT)

run-max: build-max $(DTB_MAX) $(DISK_MAX_ARTIFACT)
	$(EMULATOR_MAX) -b 0x82200000,$(DTB_MAX) \
		-l 0x80000000,$(OPENSBI_MAX) -l 0x80400000,$(UBOOT) -D $(DISK_MAX_ARTIFACT)

run-disasm: build $(DTB) $(DISK_ARTIFACT)
	$(EMULATOR_DISASM) -b 0x82200000,$(DTB) \
		-l 0x80000000,$(OPENSBI) -l 0x80400000,$(UBOOT) -D $(DISK_ARTIFACT)

run-max-disasm: build-max $(DTB_MAX) $(DISK_MAX_ARTIFACT)
	$(EMULATOR_MAX_DISASM) -b 0x82200000,$(DTB_MAX) \
		-l 0x80000000,$(OPENSBI_MAX) -l 0x80400000,$(UBOOT) -D $(DISK_MAX_ARTIFACT)

clean: clean-max
	@if [ -d $(OUT) ]; then \
		BR2_DL_DIR=$(BUILDROOT_DL) $(MAKE) -C $(BUILDROOT_SRC) O=$(OUT) BR2_EXTERNAL=$(EXTERNAL) clean; \
	fi

clean-max:
	@if [ -d $(OUT_MAX) ]; then \
		BR2_DL_DIR=$(BUILDROOT_DL) $(MAKE) -C $(BUILDROOT_SRC) O=$(OUT_MAX) BR2_EXTERNAL=$(EXTERNAL) clean; \
	fi

distclean:
	rm -rf $(OUT) $(OUT_MAX) $(ARTIFACTS)

purge-cache: distclean
	rm -rf $(BUILDROOT_SRC) $(BUILDROOT_DL) $(BUILDROOT_STAMP)
