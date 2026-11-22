# edk2-container

在 Apple Silicon Mac 上用 [Apple container](https://github.com/apple/container) 建置 [EDK2](https://github.com/tianocore/edk2) UEFI 韌體的開發環境。

- 映像：Ubuntu 24.04（arm64 原生）
- AARCH64：用原生 GCC 編 `ArmVirtPkg/ArmVirtQemu.dsc`
- X64：用 `x86_64-linux-gnu-` cross GCC 編 `OvmfPkg/OvmfPkgX64.dsc`
- 內含 `qemu-system-x86_64` / `qemu-system-aarch64` 可直接開機測試

## 需求

- Apple Silicon Mac
- 已安裝 Apple `container` CLI（`container --version` 可執行）

## 目錄結構

```
edk2-container/
├── Containerfile          # 映像定義
├── run.sh                 # Mac 端入口
├── scripts/
│   └── edk2-build.sh      # 容器內的 edk2-build 指令
└── work/                  # 掛載到容器 /work（不進 git）
    └── edk2/              # EDK2 原始碼與 Build/ 輸出
```

## 快速開始

```bash
container system start
./run.sh build          # 建立 edk2-dev 映像
./run.sh make all       # 第一次會 clone EDK2 + 編 BaseTools，再編 X64 與 AARCH64
```

輸出：

| 架構 | 檔案 |
|---|---|
| X64 | `work/edk2/Build/OvmfX64/DEBUG_GCC/FV/OVMF.fd` |
| AARCH64 | `work/edk2/Build/ArmVirtQemu-AARCH64/DEBUG_GCC/FV/QEMU_EFI.fd` |

## run.sh 指令

| 指令 | 說明 |
|---|---|
| `./run.sh build` | 啟動 container 服務並建立 `edk2-dev` 映像。改過 `Containerfile` 或 `scripts/` 後要重跑 |
| `./run.sh make [x64\|aarch64\|all] [DEBUG\|RELEASE]` | 開容器跑 `edk2-build`，跑完自動離開。預設 `all DEBUG` |
| `./run.sh shell` | 開容器進入 bash，手動操作；`exit` 離開後容器自動刪除 |

容器以 `--rm` 執行：只有 `/work`（= Mac 上的 `work/`）會保留，容器內其他變更離開即消失。

資源可用環境變數調整（預設 4 CPU / 8 GB）：

```bash
CPUS=8 MEM=12g ./run.sh make all
```

## 在容器內手動編譯

```bash
./run.sh shell
# 容器內：
cd /work/edk2 && source edksetup.sh
build -a X64     -t GCC -p MdeModulePkg/MdeModulePkg.dsc
build -a AARCH64 -t GCC -p MdeModulePkg/MdeModulePkg.dsc
```

映像已設定 `GCC_BIN=x86_64-linux-gnu-`，X64 不需另外 export。

## 用 QEMU 測試

```bash
./run.sh shell
# 容器內：
qemu-system-x86_64 -nographic -m 512 \
  -bios /work/edk2/Build/OvmfX64/DEBUG_GCC/FV/OVMF.fd

qemu-system-aarch64 -nographic -M virt -cpu cortex-a57 -m 1024 \
  -bios /work/edk2/Build/ArmVirtQemu-AARCH64/DEBUG_GCC/FV/QEMU_EFI.fd
```

`Ctrl-A` 再按 `X` 離開 QEMU。

## edk2-build 環境變數

需在 `./run.sh shell` 內設定（`run.sh` 不會轉傳）：

| 變數 | 預設 | 說明 |
|---|---|---|
| `EDK2_REF` | 空（預設分支） | 指定 tag/branch，例：`edk2-stable202505`。只在第一次 clone 時生效 |
| `TOOLCHAIN` | `GCC` | 舊版 EDK2 用 `GCC5` |
| `EDK2_DIR` | `/work/edk2` | 原始碼位置 |
| `JOBS` | `nproc` | 平行編譯數 |

```bash
EDK2_REF=edk2-stable202505 edk2-build all
```

要換 EDK2 版本：刪掉 `work/edk2` 後重跑，或在 `work/edk2` 內自行 `git checkout` + `git submodule update --init --recursive`。

## 疑難排解

| 症狀 | 原因 / 解法 |
|---|---|
| `source edksetup.sh` 印出 Usage 就結束 | 腳本參數被傳給 `edksetup.sh`；`edk2-build` 已在 source 前 `set --` 處理 |
| `Tool chain [GCC5] is not defined` | 新版 EDK2 已改名為 `GCC`（目前預設） |
| X64 出現 `gcc: unrecognized command-line option '-m64'` | 用到原生 arm64 gcc；確認 `echo $GCC_BIN` 為 `x86_64-linux-gnu-`，必要時重跑 `./run.sh build` |
| 改了 `scripts/edk2-build.sh` 沒生效 | 腳本是在建映像時複製進去的，要重跑 `./run.sh build` |
| clone / build 在掛載目錄出現權限或檔名錯誤 | macOS 檔案系統不分大小寫且透過共享掛載，可改把原始碼放在容器內部 |
