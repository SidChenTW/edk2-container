# edk2-container

在 Apple Silicon Mac 上用 [Apple container](https://github.com/apple/container) 建置 [EDK2](https://github.com/tianocore/edk2) UEFI 韌體的開發環境。

- 映像：Ubuntu 24.04（arm64 原生）
- AARCH64：用原生 GCC 編 `ArmVirtPkg/ArmVirtQemu.dsc`
- X64：用 `x86_64-linux-gnu-` cross GCC 編 `OvmfPkg/OvmfPkgX64.dsc`
- 內含 `qemu-system-x86_64` / `qemu-system-aarch64` 可直接開機測試

## 已驗證環境

- 2026-11-22：EDK2 `edk2-stable202608`，toolchain `GCC`，`DEBUG` 與 `RELEASE` 皆通過 `./run.sh test` 21 項（含 X64、AARCH64 在 QEMU 開機到 UEFI Shell 並執行 `startup.nsh`）

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
├── tests/
│   └── env-test.sh        # 環境驗證測試（./run.sh test）
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
| `./run.sh test` | 執行環境驗證測試，有任何 FAIL 時結束碼非 0 |
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

映像已設定 `GCC_BIN=x86_64-linux-gnu-`（只在 `Containerfile` 設定這一處），X64 不需另外 export。

## 環境驗證測試

```bash
./run.sh test                  # 完整測試（含 QEMU 開機，約數分鐘）
SKIP_QEMU=1 ./run.sh test      # 跳過 QEMU，只檢查環境與產物
```

`tests/` 是執行時掛載進容器的，改測試不用重建映像。log 放在 `work/test-logs/`。

| 區段 | 檢查內容 | 為什麼重要 |
|---|---|---|
| 1. 工具 | gcc、x86_64 cross gcc、nasm、iasl、python3、git、make、QEMU | build 和開機測試的前提 |
| 2. X64 toolchain | `GCC_BIN`、cross gcc 目標、接受 `-m64 -mno-red-zone` | 回歸測試：避免 `-m64` 錯誤再次出現 |
| 3. Workspace | EDK2 版本 = 固定的 `EDK2_REF`、`tools_def` 有定義 `TOOLCHAIN`、`edk2-build` 參數不干擾 `edksetup.sh` | 可重現性；回歸測試 GCC5 改名與 Usage 問題 |
| 4. 產物 | `OVMF.fd`、`QEMU_EFI.fd` 存在且非空 | 交付物 |
| 5. 開機 | X64 / AARCH64 在 QEMU 從虛擬 FAT 磁碟啟動 build 出的 `Shell.efi`，執行 `startup.nsh` 印出標記後關機 | 能編譯不代表能開機。新版 EDK2 內建 Shell 不會自動開機（commit `896907b53b`），所以改由磁碟啟動 |

可調變數（Mac 端設定即可轉傳）：`BUILD_TYPE`（預設 `DEBUG`）、`TOOLCHAIN`、`EDK2_REF`、`SKIP_QEMU`、`QEMU_TIMEOUT`（預設 180 秒）。

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

可在 Mac 端設定（`run.sh` 會用 `--env` 轉傳進容器），或在 `./run.sh shell` 內設定：

| 變數 | 預設 | 說明 |
|---|---|---|
| `EDK2_REF` | `edk2-stable202608` | 指定 tag/branch；設為空字串（`EDK2_REF=`）= 預設分支。只在第一次 clone 時生效 |
| `TOOLCHAIN` | `GCC` | 舊版 EDK2 用 `GCC5` |
| `EDK2_DIR` | `/work/edk2` | 原始碼位置 |
| `JOBS` | `nproc` | 平行編譯數 |

```bash
EDK2_REF=edk2-stable202605 ./run.sh make all   # Mac 端
TOOLCHAIN=GCC5 edk2-build all                  # 容器內
```

要換 EDK2 版本：刪掉 `work/edk2` 後重跑，或在 `work/edk2` 內自行 `git checkout` + `git submodule update --init --recursive`。

## 疑難排解

| 症狀 | 原因 / 解法 |
|---|---|
| `source edksetup.sh` 印出 Usage 就結束 | 腳本參數被傳給 `edksetup.sh`；`edk2-build` 已在 source 前 `set --` 處理 |
| `Tool chain [GCC5] is not defined` | 新版 EDK2 已改名為 `GCC`（目前預設） |
| X64 出現 `gcc: unrecognized command-line option '-m64'` | 用到原生 arm64 gcc；確認 `echo $GCC_BIN` 為 `x86_64-linux-gnu-`，必要時重跑 `./run.sh build` |
| 改了 `scripts/edk2-build.sh` 沒生效 | 腳本是在建映像時複製進去的，要重跑 `./run.sh build` |
| `zsh: permission denied: ./run.sh` | 執行權限遺失，執行 `chmod +x run.sh scripts/edk2-build.sh` |
| clone / build 在掛載目錄出現權限或檔名錯誤 | macOS 檔案系統不分大小寫且透過共享掛載，可改把原始碼放在容器內部 |
