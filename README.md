# edk2-container

**English** | [繁體中文](README.zh-TW.md)

A development environment for building [EDK2](https://github.com/tianocore/edk2) UEFI firmware on Apple Silicon Macs using [Apple container](https://github.com/apple/container).

- Image: Ubuntu 24.04 (native arm64)
- AARCH64: builds `ArmVirtPkg/ArmVirtQemu.dsc` with native GCC
- X64: builds `OvmfPkg/OvmfPkgX64.dsc` with the `x86_64-linux-gnu-` cross GCC
- Includes `qemu-system-x86_64` / `qemu-system-aarch64` for boot testing

## Verified environment

- 2026-11-22: EDK2 `edk2-stable202608`, toolchain `GCC`; both `DEBUG` and `RELEASE` pass all 21 checks of `./run.sh test` (including X64 and AARCH64 booting to the UEFI Shell in QEMU and running `startup.nsh`)
  - Apple `container` CLI 1.7.1 (commit `a15b460`), Apple Silicon Mac
  - Base image `ubuntu:24.04` (`sha256:9c7f200c07e3d4a03e7249d2c16bf66a51120fb876aa2242cf31451412543289`)

> Note: `Containerfile` uses the `ubuntu:24.04` tag rather than a fixed digest, so rebuilds pick up newer packages and security updates, but results may differ from the verification above.
> For fully reproducible builds, change it to `FROM docker.io/library/ubuntu:24.04@sha256:9c7f200c07e3d4a03e7249d2c16bf66a51120fb876aa2242cf31451412543289`.

## Requirements

- Apple Silicon Mac
- Apple `container` CLI installed (`container --version` works)

## Layout

```
edk2-container/
├── Containerfile          # Image definition
├── run.sh                 # Entry point on the Mac
├── LICENSE                # MIT
├── scripts/
│   └── edk2-build.sh      # edk2-build command inside the container
├── tests/
│   └── env-test.sh        # Environment validation tests (./run.sh test)
└── work/                  # Mounted at /work in the container (not in git)
    └── edk2/              # EDK2 source and Build/ output
```

## Quick start

```bash
container system start
./run.sh build          # Build the edk2-dev image
./run.sh make all       # First run clones EDK2 and builds BaseTools, then builds X64 and AARCH64
```

Output:

| Arch | File |
|---|---|
| X64 | `work/edk2/Build/OvmfX64/DEBUG_GCC/FV/OVMF.fd` |
| AARCH64 | `work/edk2/Build/ArmVirtQemu-AARCH64/DEBUG_GCC/FV/QEMU_EFI.fd` |

## run.sh commands

| Command | Description |
|---|---|
| `./run.sh build` | Start the container service and build the `edk2-dev` image. Re-run after changing `Containerfile` or `scripts/` |
| `./run.sh make [x64\|aarch64\|all] [DEBUG\|RELEASE]` | Run `edk2-build` in a container, then exit. Default: `all DEBUG` |
| `./run.sh test` | Run the environment validation tests; exits non-zero if anything FAILs |
| `./run.sh shell` | Open a bash shell in a container; the container is removed on `exit` |

Containers run with `--rm`: only `/work` (= `work/` on the Mac) persists; any other changes inside the container are lost on exit.

Resources can be adjusted with environment variables (default 4 CPUs / 8 GB):

```bash
CPUS=8 MEM=12g ./run.sh make all
```

## Building manually inside the container

```bash
./run.sh shell
# Inside the container:
cd /work/edk2 && source edksetup.sh
build -a X64     -t GCC -p MdeModulePkg/MdeModulePkg.dsc
build -a AARCH64 -t GCC -p MdeModulePkg/MdeModulePkg.dsc
```

The image sets `GCC_BIN=x86_64-linux-gnu-` (only in `Containerfile`), so X64 builds need no extra export.

## Environment validation tests

```bash
./run.sh test                  # Full test, including QEMU boot (a few minutes)
SKIP_QEMU=1 ./run.sh test      # Skip QEMU; check only the environment and build output
```

`tests/` is mounted into the container at run time, so changing tests does not require rebuilding the image. Logs go to `work/test-logs/`.

| Section | Checks | Why it matters |
|---|---|---|
| 1. Tools | gcc, x86_64 cross gcc, nasm, iasl, python3, git, make, QEMU | Prerequisites for building and boot testing |
| 2. X64 toolchain | `GCC_BIN`, cross gcc target, accepts `-m64 -mno-red-zone` | Regression test: keeps the `-m64` error from coming back |
| 3. Workspace | EDK2 version = pinned `EDK2_REF`, `tools_def` defines `TOOLCHAIN`, `edk2-build` arguments don't interfere with `edksetup.sh` | Reproducibility; regression tests for the GCC5 rename and the Usage issue |
| 4. Output | `OVMF.fd` and `QEMU_EFI.fd` exist and are non-empty | The deliverables |
| 5. Boot | X64 / AARCH64 boot the built `Shell.efi` from a virtual FAT disk in QEMU, run `startup.nsh` to print a marker, then shut down | Building is not booting. Newer EDK2 no longer autoboots the built-in Shell (commit `896907b53b`), so it is booted from disk |

Tunable variables (set on the Mac; forwarded automatically): `BUILD_TYPE` (default `DEBUG`), `TOOLCHAIN`, `EDK2_REF`, `SKIP_QEMU`, `QEMU_TIMEOUT` (default 180 seconds).

## Testing with QEMU

In newer EDK2 (commit `896907b53b`) the built-in UEFI Shell **does not autoboot**; booting with just `-bios` stops at
`BdsDxe: No bootable option or device was found.`. To get to the Shell, boot the built `Shell.efi` from a virtual FAT disk (the same method as `./run.sh test`, verified):

```bash
./run.sh shell
# Inside the container:
B=/work/edk2/Build

# X64
mkdir -p /tmp/esp/EFI/BOOT && cp $B/OvmfX64/DEBUG_GCC/X64/Shell.efi /tmp/esp/EFI/BOOT/BOOTX64.EFI
qemu-system-x86_64 -nographic -m 512 -net none \
  -bios $B/OvmfX64/DEBUG_GCC/FV/OVMF.fd \
  -drive if=none,id=esp,format=raw,file=fat:rw:/tmp/esp -device virtio-blk-pci,drive=esp

# AARCH64
mkdir -p /tmp/esp-aa64/EFI/BOOT && cp $B/ArmVirtQemu-AARCH64/DEBUG_GCC/AARCH64/Shell.efi /tmp/esp-aa64/EFI/BOOT/BOOTAA64.EFI
qemu-system-aarch64 -nographic -M virt -cpu cortex-a57 -m 1024 -net none \
  -bios $B/ArmVirtQemu-AARCH64/DEBUG_GCC/FV/QEMU_EFI.fd \
  -drive if=none,id=esp,format=raw,file=fat:rw:/tmp/esp-aa64 -device virtio-blk-pci,drive=esp
```

Other `.efi` files placed in `/tmp/esp` can be run from the Shell after switching with `fs0:`.
Alternative (not verified): press any key at `Press any key to enter the Boot Manager Menu` and choose `EFI Internal Shell`.

Press `Ctrl-A` then `X` to quit QEMU. For RELEASE builds, replace `DEBUG_GCC` with `RELEASE_GCC` in the paths.

## edk2-build environment variables

Set them on the Mac (`run.sh` forwards them with `--env`) or inside `./run.sh shell`:

| Variable | Default | Description |
|---|---|---|
| `EDK2_REF` | `edk2-stable202608` | Tag/branch to use; an empty string (`EDK2_REF=`) means the default branch. Only applies on the first clone |
| `TOOLCHAIN` | `GCC` | Use `GCC5` for older EDK2 |
| `EDK2_DIR` | `/work/edk2` | Source location |
| `JOBS` | `nproc` | Parallel build jobs |

```bash
EDK2_REF=edk2-stable202605 ./run.sh make all   # On the Mac
TOOLCHAIN=GCC5 edk2-build all                  # Inside the container (only for older EDK2 that still has GCC5)
```

To switch EDK2 versions: delete `work/edk2` and re-run, or run `git checkout` + `git submodule update --init --recursive` inside `work/edk2`.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `source edksetup.sh` prints Usage and exits | Script arguments were passed to `edksetup.sh`; `edk2-build` clears them with `set --` before sourcing |
| `Tool chain [GCC5] is not defined` | Newer EDK2 renamed it to `GCC` (the current default) |
| X64 fails with `gcc: unrecognized command-line option '-m64'` | The native arm64 gcc was used; check that `echo $GCC_BIN` prints `x86_64-linux-gnu-`, and re-run `./run.sh build` if needed |
| Changes to `scripts/edk2-build.sh` have no effect | The script is copied in at image build time; re-run `./run.sh build` |
| `zsh: permission denied: ./run.sh` | Execute permission was lost; run `chmod +x run.sh scripts/edk2-build.sh` |
| Permission or filename errors during clone/build in the mounted folder | The macOS file system is case-insensitive and shared via a mount; consider keeping the source inside the container |

## License

The scripts and documentation in this repo are licensed under the [MIT License](LICENSE).

The EDK2 source downloaded by `edk2-build` (`work/edk2`, not part of this repo) is under its own license, mainly BSD-2-Clause-Patent; see EDK2's `License.txt`.
