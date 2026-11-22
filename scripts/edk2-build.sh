#!/usr/bin/env bash
# 用法: edk2-build [x64|aarch64|all] [DEBUG|RELEASE]
set -euo pipefail
TARGET_ARCH=${1:-all}
BUILD_TYPE=${2:-DEBUG}
EDK2_DIR=${EDK2_DIR:-/work/edk2}
EDK2_REF=${EDK2_REF:-}            # 例: edk2-stable202505；空值 = 預設分支
TOOLCHAIN=${TOOLCHAIN:-GCC}       # 舊版 EDK2 可設 TOOLCHAIN=GCC5
JOBS=${JOBS:-$(nproc)}

if [ ! -d "$EDK2_DIR/.git" ]; then
  git clone https://github.com/tianocore/edk2.git "$EDK2_DIR"
  [ -n "$EDK2_REF" ] && git -C "$EDK2_DIR" checkout "$EDK2_REF"
  git -C "$EDK2_DIR" submodule update --init --recursive
fi

cd "$EDK2_DIR"
[ -x BaseTools/Source/C/bin/GenFw ] || make -C BaseTools -j"$JOBS"
set --  # 清空參數，避免 edksetup.sh 把 build 參數當成它的選項
set +u; source edksetup.sh; set -u

export GCC_BIN=x86_64-linux-gnu-                 # 新版 tools_def: GCC_X64_PREFIX = ENV(GCC_BIN)
export ${TOOLCHAIN}_X64_PREFIX=x86_64-linux-gnu-   # 舊版 GCC5 相容

build_x64()     { build -a X64     -t "$TOOLCHAIN" -b "$BUILD_TYPE" -n "$JOBS" -p OvmfPkg/OvmfPkgX64.dsc; }
build_aarch64() { build -a AARCH64 -t "$TOOLCHAIN" -b "$BUILD_TYPE" -n "$JOBS" -p ArmVirtPkg/ArmVirtQemu.dsc; }

case "$TARGET_ARCH" in
  x64)     build_x64 ;;
  aarch64) build_aarch64 ;;
  all)     build_x64; build_aarch64 ;;
  *) echo "未知目標: $TARGET_ARCH (x64|aarch64|all)" >&2; exit 1 ;;
esac

echo "完成。輸出："
ls -1 Build/OvmfX64/${BUILD_TYPE}_${TOOLCHAIN}/FV/OVMF.fd 2>/dev/null || true
ls -1 Build/ArmVirtQemu-AARCH64/${BUILD_TYPE}_${TOOLCHAIN}/FV/QEMU_EFI.fd 2>/dev/null || true
