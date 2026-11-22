# EDK2 開發環境（arm64 原生映像，含 X64 cross 與 AARCH64 原生 toolchain）
FROM docker.io/library/ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential uuid-dev acpica-tools nasm \
      python3 python3-venv python-is-python3 \
      git ca-certificates \
      gcc-x86-64-linux-gnu g++-x86-64-linux-gnu \
      qemu-system-x86 qemu-system-arm \
    && rm -rf /var/lib/apt/lists/*

# EDK2 GCC toolchain 的 X64 cross 前綴（GCC_X64_PREFIX = ENV(GCC_BIN)）；AARCH64 用 GCC_AARCH64_PREFIX，不受影響
ENV GCC_BIN=x86_64-linux-gnu-

COPY scripts/edk2-build.sh /usr/local/bin/edk2-build
RUN chmod +x /usr/local/bin/edk2-build

WORKDIR /work
CMD ["/bin/bash"]
