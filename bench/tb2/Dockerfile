# comide and everything it runs with, built once for Linux and packed as one directory
# that a Terminal-Bench task container can take in: comide, golemide, and the tools comide
# uses when they are there (gramide, hew, ctxgate), and porta to confine the run.
#
# Built on Debian bullseye (glibc 2.31), the oldest libc among the Terminal-Bench 2.0 task
# images: a binary linked here runs on every one of them (bookworm, trixie, Ubuntu 24.04).
# The published Almide binaries need glibc 2.39, so Almide is built here from its tag.
FROM rust:1-bullseye

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG ALMIDE_REF=v0.64.0
ARG PORTA_VERSION=v0.6.16

RUN git init -q /tmp/almide && cd /tmp/almide \
 && git remote add origin https://github.com/almide/almide \
 && git fetch -q --depth 1 origin "refs/tags/${ALMIDE_REF}:refs/tags/${ALMIDE_REF}" && git checkout -q "${ALMIDE_REF}" \
 && cargo build --release --locked --bin almide > /tmp/almide-build.log 2>&1 \
 || { tail -30 /tmp/almide-build.log; exit 1; }
RUN install -m 0755 /tmp/almide/target/release/almide /usr/local/bin/almide && rm -rf /tmp/almide && almide --version

# porta from its tag, built here (almide/porta#35). The released Linux binary needs glibc
# 2.39 and libssl.so.3, so it does not start on bookworm or python:*-slim: its reqwest asks
# for rustls without turning off the default native-tls. Built here with default-features
# = false it is rustls only, and links this glibc. The better fix, a static musl build as
# Codex ships, waits on almide/almide#2772.
RUN git clone -q --depth 1 --branch "${PORTA_VERSION}" https://github.com/almide/porta /tmp/porta && cd /tmp/porta \
 && sed -i 's/^reqwest = { version = \("[^"]*"\), features/reqwest = { version = \1, default-features = false, features/' almide.toml \
 && grep '^reqwest' almide.toml \
 && almide build --release src/main.almd -o porta > /tmp/porta-build.log 2>&1 \
 || { tail -30 /tmp/porta-build.log; exit 1; }
RUN mkdir -p /bundle/bin && install -m 0755 /tmp/porta/porta /bundle/bin/porta && rm -rf /tmp/porta \
 && ! ldd /bundle/bin/porta | grep -q ssl && /bundle/bin/porta --version

COPY src/ /src/
RUN for t in gramide-cli:gramide hew:hew ctxgate:ctxgate golemide:golemide comide:comide; do \
      dir="${t%%:*}"; bin="${t##*:}"; \
      ( cd "/src/$dir" && almide build --release src/main.almd -o "$bin" > "/tmp/$bin.log" 2>&1 && install -m 0755 "$bin" "/bundle/bin/$bin" ) \
      || { echo "== $dir failed"; tail -30 "/tmp/$bin.log"; exit 1; }; \
    done \
 && /bundle/bin/comide --help > /dev/null && /bundle/bin/golemide --version \
 && objdump -T /bundle/bin/* | grep -o 'GLIBC_[0-9.]*' | sort -uV | tail -1 > /bundle/glibc-needed \
 && cat /bundle/glibc-needed
