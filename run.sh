#!/usr/bin/env bash
# Mac 端入口。用法:
#   ./run.sh build              建立映像
#   ./run.sh shell              進入互動 shell
#   ./run.sh make [x64|aarch64|all] [DEBUG|RELEASE]
#   ./run.sh test               環境驗證測試
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p work
IMAGE=edk2-dev
RUN_OPTS=(--rm -it --cpus "${CPUS:-4}" --memory "${MEM:-8g}" --volume "$PWD/work:/work")
# 把有設定的 edk2-build 變數轉傳進容器
for v in EDK2_REF TOOLCHAIN JOBS BUILD_TYPE SKIP_QEMU QEMU_TIMEOUT; do
  if [ -n "${!v+x}" ]; then RUN_OPTS+=(--env "$v=${!v}"); fi
done

case "${1:-}" in
  build) container system start >/dev/null 2>&1 || true
         container build --tag "$IMAGE" --file Containerfile . ;;
  shell) container run "${RUN_OPTS[@]}" "$IMAGE" ;;
  make)  shift; container run "${RUN_OPTS[@]}" "$IMAGE" edk2-build "$@" ;;
  test)  container run "${RUN_OPTS[@]}" --volume "$PWD/tests:/tests" "$IMAGE" bash /tests/env-test.sh ;;
  *) sed -n '2,7p' "$0"; exit 1 ;;
esac
