# comide alone, built for Linux, to be put into a Terminal-Bench task's container.
#
# Built on Debian bullseye (glibc 2.31), the oldest libc among the Terminal-Bench 2 task
# images: a binary linked here runs on every one of them (bookworm, trixie, Ubuntu 24.04).
# The published Almide binaries need glibc 2.39, so Almide is built here from its commit.
# The first instructions are, to the letter, those of bench/tb2/Dockerfile, so a machine
# that built that one has these layers already (which is why PORTA_REF is named here).
FROM rust:1-bullseye

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG ALMIDE_REF=250fb6dc3f9f640aaeacc40192e74ae8f87e1fbc
ARG PORTA_REF=3c79e54adadc

RUN git init -q /tmp/almide && cd /tmp/almide \
 && git remote add origin https://github.com/almide/almide \
 && git fetch -q --depth 1 origin "${ALMIDE_REF}" && git checkout -q FETCH_HEAD \
 && cargo build --release --locked --bin almide > /tmp/almide-build.log 2>&1 \
 || { tail -30 /tmp/almide-build.log; exit 1; }
RUN install -m 0755 /tmp/almide/target/release/almide /usr/local/bin/almide && rm -rf /tmp/almide && almide --version

COPY src/ /src/
RUN cd /src && almide build --release src/main.almd -o comide > /tmp/comide.log 2>&1 \
 || { tail -30 /tmp/comide.log; exit 1; }
RUN mkdir -p /out && install -m 0755 /src/comide /out/comide && /out/comide --version \
 && objdump -T /out/comide | grep -o 'GLIBC_[0-9.]*' | sort -uV | tail -1 > /out/glibc-needed && cat /out/glibc-needed
