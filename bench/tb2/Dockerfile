# comide and everything it runs with, built once for Linux and packed as one directory
# that a Terminal-Bench task container can take in: comide, golemide, and the tools comide
# uses when they are there (gramide, hew, ctxgate), porta to confine the run, and onogoro to
# confine it one tool call at a time (CONFINE=onogoro).
#
# Built on Debian bullseye (glibc 2.31), the oldest libc among the Terminal-Bench 2.0 task
# images: a binary linked here runs on every one of them (bookworm, trixie, Ubuntu 24.04).
# The published Almide binaries need glibc 2.39, so Almide is built here from its tag.
FROM rust:1-bullseye

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# Both from develop until they release what onogoro rests on: Almide's HTTP client
# honouring HTTPS_PROXY and a proxy's CA (almide/almide#2833), and porta's credential
# broker (almide/porta#42). A commit, not a branch, so the bundle can be named.
ARG ALMIDE_REF=7b563f7ee30b7715fd1cf8b0631eee0f22c8c598
ARG PORTA_REF=d51cccbf991f

RUN git init -q /tmp/almide && cd /tmp/almide \
 && git remote add origin https://github.com/almide/almide \
 && git fetch -q --depth 1 origin "${ALMIDE_REF}" && git checkout -q FETCH_HEAD \
 && cargo build --release --locked --bin almide > /tmp/almide-build.log 2>&1 \
 || { tail -30 /tmp/almide-build.log; exit 1; }
RUN install -m 0755 /tmp/almide/target/release/almide /usr/local/bin/almide && rm -rf /tmp/almide && almide --version

# porta built here, with this glibc. Its develop is rustls only (almide/porta#35), so the
# binary needs no libssl. porta is built with the Almide above rather than its own pin
# (0.63): the pin is about porta's integration suite and process.exit's range
# (almide/almide#2780), which this build does not run.
RUN git init -q /tmp/porta && cd /tmp/porta \
 && git remote add origin https://github.com/almide/porta \
 && git fetch -q origin develop && git checkout -q "${PORTA_REF}" \
 && grep '^reqwest.*default-features = false' almide.toml \
 && almide build --release src/main.almd -o porta > /tmp/porta-build.log 2>&1 \
 || { tail -30 /tmp/porta-build.log; exit 1; }
RUN mkdir -p /bundle/bin && install -m 0755 /tmp/porta/porta /bundle/bin/porta && rm -rf /tmp/porta \
 && ! ldd /bundle/bin/porta | grep -q ssl && /bundle/bin/porta --version \
 && /bundle/bin/porta run --help | grep -q -- --credential

COPY src/ /src/
RUN for t in gramide-cli:gramide hew:hew ctxgate:ctxgate golemide:golemide comide:comide onogoro:onogoro; do \
      dir="${t%%:*}"; bin="${t##*:}"; \
      ( cd "/src/$dir" && almide build --release src/main.almd -o "$bin" > "/tmp/$bin.log" 2>&1 && install -m 0755 "$bin" "/bundle/bin/$bin" ) \
      || { echo "== $dir failed"; tail -30 "/tmp/$bin.log"; exit 1; }; \
    done \
 && /bundle/bin/comide --help > /dev/null && /bundle/bin/golemide --version \
 && objdump -T /bundle/bin/* | grep -o 'GLIBC_[0-9.]*' | sort -uV | tail -1 > /bundle/glibc-needed \
 && cat /bundle/glibc-needed
