# ─── Stage 1: Build ───────────────────────────────────────────────────────────
FROM golang:latest AS builder

RUN apt-get update && apt-get install -y \
    git make \
    libsecret-1-dev \
    libfido2-dev \
    libcbor-dev \
    libssl-dev \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth=1 https://github.com/ProtonMail/proton-bridge.git /build
WORKDIR /build

# Critical: patch bridge to listen on 0.0.0.0 instead of 127.0.0.1
# Without this, no other container can reach the IMAP/SMTP ports
RUN sed -i 's/127\.0\.0\.1/0.0.0.0/g' internal/constants/constants.go

RUN make build-nogui

# ─── Stage 2: Runtime ─────────────────────────────────────────────────────────
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    libsecret-1-0 \
    libglib2.0-0 \
    pass \
    gnupg \
    dbus-x11 \
    gnome-keyring \
    procps \
    && rm -rf /var/lib/apt/lists/*

# The launcher (proton-bridge) looks for the actual binary (bridge) in the same directory
COPY --from=builder /build/proton-bridge /protonmail/proton-bridge
COPY --from=builder /build/bridge /protonmail/bridge
COPY entrypoint.sh /protonmail/entrypoint.sh
COPY gpgparams /protonmail/gpgparams

RUN chmod +x /protonmail/entrypoint.sh

VOLUME /root
EXPOSE 25 143

ENTRYPOINT ["/protonmail/entrypoint.sh"]