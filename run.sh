#!/usr/bin/env bash
# Mac 端入口。用法:
#   ./run.sh build              建立映像
#   ./run.sh shell              進入互動 shell
#   ./run.sh make [x64|aarch64|all] [DEBUG|RELEASE]
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p work
IMAGE=edk2-dev
RUN_OPTS=(--rm -it --cpus "${CPUS:-4}" --memory "${MEM:-8g}" --volume "$PWD/work:/work")

case "${1:-}" in
  build) container system start >/dev/null 2>&1 || true
         container build --tag "$IMAGE" --file Containerfile . ;;
  shell) container run "${RUN_OPTS[@]}" "$IMAGE" ;;
  make)  shift; container run "${RUN_OPTS[@]}" "$IMAGE" edk2-build "$@" ;;
  *) sed -n '2,6p' "$0"; exit 1 ;;
esac
