#!/usr/bin/env bash
# EDK2 環境驗證測試（在容器內執行：./run.sh test）
# 每一項都附上「為什麼重要」，失敗時印出，方便判斷影響。
set -uo pipefail

EDK2_DIR=${EDK2_DIR:-/work/edk2}
TOOLCHAIN=${TOOLCHAIN:-GCC}
BUILD_TYPE=${BUILD_TYPE:-DEBUG}
EXPECTED_REF=${EDK2_REF-edk2-stable202608}   # 與 edk2-build 預設一致
QEMU_TIMEOUT=${QEMU_TIMEOUT:-180}
LOG_DIR=${LOG_DIR:-/work/test-logs}
mkdir -p "$LOG_DIR"

PASS=0; FAIL=0; SKIP=0
ok()   { echo "PASS  $1"; PASS=$((PASS+1)); }
bad()  { echo "FAIL  $1"; echo "      為什麼重要：$2"; [ -n "${3:-}" ] && echo "      細節：$3"; FAIL=$((FAIL+1)); }
skip() { echo "SKIP  $1（$2）"; SKIP=$((SKIP+1)); }

X64_FD=$EDK2_DIR/Build/OvmfX64/${BUILD_TYPE}_${TOOLCHAIN}/FV/OVMF.fd
AA64_FD=$EDK2_DIR/Build/ArmVirtQemu-AARCH64/${BUILD_TYPE}_${TOOLCHAIN}/FV/QEMU_EFI.fd

echo "== 1. 映像內的工具 =="
for t in gcc x86_64-linux-gnu-gcc nasm iasl python3 git make qemu-system-x86_64 qemu-system-aarch64; do
  if command -v "$t" >/dev/null; then ok "工具存在：$t"
  else bad "工具存在：$t" "EDK2 build 或 QEMU 測試需要它；缺少代表 Containerfile 套件清單被改壞或映像沒重建"; fi
done

echo "== 2. X64 cross toolchain =="
if [ "${GCC_BIN:-}" = "x86_64-linux-gnu-" ]; then ok "GCC_BIN=x86_64-linux-gnu-"
else bad "GCC_BIN=x86_64-linux-gnu-" "EDK2 的 GCC_X64_PREFIX = ENV(GCC_BIN)；沒設會用 arm64 原生 gcc 編 X64" "目前值：[${GCC_BIN:-}]"; fi

m=$(${GCC_BIN:-}gcc -dumpmachine 2>/dev/null || true)
case "$m" in x86_64*) ok "\${GCC_BIN}gcc 目標為 x86_64（$m）" ;;
  *) bad "\${GCC_BIN}gcc 目標為 x86_64" "X64 韌體必須用 x86_64 目標的編譯器" "dumpmachine=[$m]" ;; esac

# 回歸測試：曾出現 gcc: unrecognized command-line option '-m64' / '-mno-red-zone'
if echo 'int f(void){return 0;}' | ${GCC_BIN:-}gcc -m64 -mno-red-zone -maccumulate-outgoing-args -x c -c -o /dev/null - 2>"$LOG_DIR/x64-flags.log"; then
  ok "X64 編譯器接受 -m64 -mno-red-zone -maccumulate-outgoing-args"
else bad "X64 編譯器接受 EDK2 的 x86 旗標" "EDK2 X64 build 一定會帶這些旗標；失敗就是 2026-11-22 的 -m64 錯誤又回來了" "$(head -3 "$LOG_DIR/x64-flags.log")"; fi

m=$(gcc -dumpmachine 2>/dev/null || true)
case "$m" in aarch64*) ok "原生 gcc 目標為 aarch64（$m）" ;;
  *) bad "原生 gcc 目標為 aarch64" "AARCH64 build 依賴 GCC_AARCH64_PREFIX 未設、直接用原生 gcc" "dumpmachine=[$m]" ;; esac

echo "== 3. EDK2 workspace =="
if [ ! -d "$EDK2_DIR/.git" ]; then
  bad "EDK2 原始碼存在" "所有 build 都需要；先執行 ./run.sh make" "$EDK2_DIR 不存在"
else
  ok "EDK2 原始碼存在"
  cur=$(git -C "$EDK2_DIR" describe --tags 2>/dev/null || echo unknown)
  if [ -z "$EXPECTED_REF" ]; then
    skip "EDK2 版本符合固定版本" "EDK2_REF 設為空，刻意使用預設分支；目前 $cur"
  elif [ "$cur" = "$EXPECTED_REF" ]; then ok "EDK2 版本 = $EXPECTED_REF"
  else bad "EDK2 版本 = $EXPECTED_REF" "固定版本才能讓每次 build 可重現；不符代表 work/edk2 是舊 clone 或被手動切換" "目前 $cur（重新對齊：刪除 work/edk2 後 ./run.sh make all）"; fi

  if grep -q "^\*_${TOOLCHAIN}_X64_CC_PATH" "$EDK2_DIR/Conf/tools_def.txt" 2>/dev/null \
     || grep -q "^\*_${TOOLCHAIN}_X64_CC_PATH" "$EDK2_DIR/BaseTools/Conf/tools_def.template" 2>/dev/null; then
    ok "tools_def 定義 toolchain $TOOLCHAIN"
  else bad "tools_def 定義 toolchain $TOOLCHAIN" "回歸測試：新版 EDK2 移除了 GCC5；TOOLCHAIN 必須是這版 EDK2 認得的名稱"; fi

  # 回歸測試：edk2-build 的參數曾被傳進 edksetup.sh，導致印出 Usage 就結束。
  # 給一個無效目標：若 edksetup.sh 正常，腳本會走到 case 並印出「未知目標」。
  out=$(edk2-build __invalid__ 2>&1); rc=$?
  if [ $rc -ne 0 ] && grep -q "未知目標" <<<"$out" && ! grep -q "Usage: edksetup.sh" <<<"$out"; then
    ok "edk2-build 參數不會干擾 edksetup.sh"
  else bad "edk2-build 參數不會干擾 edksetup.sh" "若參數漏進 edksetup.sh，整個 build 會在編譯前就中止" "rc=$rc，輸出末行：$(tail -1 <<<"$out")"; fi
fi

echo "== 4. Build 產物（$BUILD_TYPE / $TOOLCHAIN）=="
for fd in "$X64_FD" "$AA64_FD"; do
  if [ -s "$fd" ]; then ok "存在且非空：${fd#$EDK2_DIR/}"
  else bad "存在：${fd#$EDK2_DIR/}" "這是交付的韌體映像；不存在代表 build 失敗或還沒編" "先執行 ./run.sh make all $BUILD_TYPE"; fi
done

echo "== 5. QEMU 開機到 UEFI Shell =="
# 新版 EDK2（commit 896907b53b）把內建 Shell 改為 APP 類別、不自動開機，
# 所以這裡用 QEMU 虛擬 FAT 磁碟，把 build 出來的 Shell.efi 放成可移除媒體的預設開機檔，
# 再由 startup.nsh 印出標記並關機。看到標記 = 韌體開機成功 + Shell 能執行腳本。
MARKER=EDK2_ENV_TEST_SHELL_OK
boot() { # $1=名稱 $2=韌體 $3=Shell.efi $4=預設開機檔名 $5...=qemu 指令
  local name=$1 fd=$2 shell=$3 bootname=$4; shift 4
  if [ "${SKIP_QEMU:-0}" = 1 ]; then skip "$name 開機" "SKIP_QEMU=1"; return; fi
  if [ ! -s "$fd" ]; then skip "$name 開機" "韌體不存在，見上一節"; return; fi
  if [ ! -s "$shell" ]; then bad "$name Shell.efi 存在" "開機測試要用它當開機程式；BUILD_SHELL 可能被關掉" "$shell"; return; fi
  local esp="$LOG_DIR/esp-$name" log="$LOG_DIR/qemu-$name.log"
  rm -rf "$esp"; mkdir -p "$esp/EFI/BOOT"
  cp "$shell" "$esp/EFI/BOOT/$bootname"
  printf 'echo %s\r\nreset -s\r\n' "$MARKER" > "$esp/startup.nsh"
  timeout "$QEMU_TIMEOUT" "$@" -bios "$fd" -nographic -net none \
    -drive if=none,id=esp,format=raw,file=fat:rw:"$esp" -device virtio-blk-pci,drive=esp \
    </dev/null >"$log" 2>&1
  local rc=$?
  if grep -aq "$MARKER" "$log"; then
    ok "$name 開機到 UEFI Shell 並執行 startup.nsh"
    [ $rc -eq 124 ] && echo "      注意：已看到標記，但 QEMU 沒有自行關機（reset -s 未生效），被 timeout 結束"
  else bad "$name 開機到 UEFI Shell" "能編譯不代表能開機；這是韌體真正可用的最低證明" "${QEMU_TIMEOUT}s 內沒看到 $MARKER（rc=$rc），見 ${log}"; fi
}
X64_SHELL=$EDK2_DIR/Build/OvmfX64/${BUILD_TYPE}_${TOOLCHAIN}/X64/Shell.efi
AA64_SHELL=$EDK2_DIR/Build/ArmVirtQemu-AARCH64/${BUILD_TYPE}_${TOOLCHAIN}/AARCH64/Shell.efi
boot x64     "$X64_FD"  "$X64_SHELL"  BOOTX64.EFI  qemu-system-x86_64  -m 512
boot aarch64 "$AA64_FD" "$AA64_SHELL" BOOTAA64.EFI qemu-system-aarch64 -M virt -cpu cortex-a57 -m 1024

echo
echo "結果：PASS $PASS / FAIL $FAIL / SKIP $SKIP（log：$LOG_DIR）"
[ $FAIL -eq 0 ]
