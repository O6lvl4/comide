# The lab's image: nautra, comide's two halves that run under it, and the tools a terminal
# needs.
#
# Everything the terminal may run is in this image's system directories. Nothing is read
# from the machine that starts the lab, so a closed terminal has a shell, Python, a C
# compiler, git and curl without its reads being widened.
#
# The first instructions are, to the letter, those of bench/tb2/Dockerfile and
# bench/tb2/linux/Dockerfile, so a machine that built one of those has these layers
# already (which is why PORTA_REF is named here).
FROM rust:1-bullseye AS build

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG ALMIDE_REF=250fb6dc3f9f640aaeacc40192e74ae8f87e1fbc
ARG PORTA_REF=3c79e54adadc

RUN git init -q /tmp/almide && cd /tmp/almide \
 && git remote add origin https://github.com/almide/almide \
 && git fetch -q --depth 1 origin "${ALMIDE_REF}" && git checkout -q FETCH_HEAD \
 && cargo build --release --locked --bin almide > /tmp/almide-build.log 2>&1 \
 || { tail -30 /tmp/almide-build.log; exit 1; }
RUN install -m 0755 /tmp/almide/target/release/almide /usr/local/bin/almide && rm -rf /tmp/almide && almide --version

# AGENT: the file in src/ the agent under nautra is built from (nautra/lab/build.sh).
ARG AGENT=enclosed
COPY almide.toml almide.lock /src/
COPY src/ /src/src/
RUN cd /src && mkdir -p /out \
 && { almide build --release src/shelltool.almd -o /out/comide-shell > /tmp/shell.log 2>&1 \
      || { tail -30 /tmp/shell.log; exit 1; }; } \
 && { almide build "src/${AGENT}.almd" --target wasm -o /out/comide.wasm > /tmp/agent.log 2>&1 \
      || { tail -30 /tmp/agent.log; exit 1; }; }

FROM ghcr.io/aid-on/nautra:0.1.0
USER root
RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends python3 python3-pytest python-is-python3 gcc libc6-dev make git curl ca-certificates procps > /dev/null \
 && rm -rf /var/lib/apt/lists/*
COPY --from=build /out/comide-shell /out/comide.wasm /opt/comide/
COPY relay.py target.py sink.py /opt/lab/
# The workspace, the terminal's state and the run's record: on the container's own disk
# (a folder shared with macOS is not writable under nautra's confinement).
RUN mkdir -p /lab/work /lab/state /lab/log /lab/run && chown -R nautra:nautra /lab
USER nautra
WORKDIR /lab
