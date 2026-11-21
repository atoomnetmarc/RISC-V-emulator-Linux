#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Put the boot files in the root filesystem so U-Boot can load them from the
# single disk partition.
set -eu

target_dir=$1

mkdir -p "$target_dir/boot"
cp "$BINARIES_DIR/Image" "$target_dir/boot/Image"
cp "$BINARIES_DIR/linux.dtb" "$target_dir/boot/linux.dtb"
