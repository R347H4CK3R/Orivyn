#!/bin/sh
set -eu
cp "$TARGET_DIR/lib/grub/i386-pc/boot.img" "$BINARIES_DIR/boot.img"
# S99desktop owns Xorg and its session; upstream's bare server races it.
rm -f "$TARGET_DIR/etc/init.d/S40xorg"

# Compile original local guest helper with the pinned Buildroot cross-toolchain.
BOARD_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
"$HOST_DIR/bin/i686-buildroot-linux-musl-gcc" -Os -Wall -Wextra -Werror "$BOARD_DIR/orivyn-ready-shell.c" -lX11 -o "$TARGET_DIR/usr/bin/orivyn-ready-shell"
