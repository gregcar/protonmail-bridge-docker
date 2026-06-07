#!/bin/bash
set -e

export GNUPGHOME="/root/.gnupg"

# ── Start DBus session (required for keychain/secret service) ─────────────────
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    echo "[bridge] Starting DBus session..."
    eval "$(dbus-launch --sh-syntax)"
    export DBUS_SESSION_BUS_ADDRESS
fi

# ── Start secret service (gnome-keyring) ──────────────────────────────────────
eval "$(gnome-keyring-daemon --start --components=secrets)"
export GNOME_KEYRING_CONTROL

# ── Unlock/create the default login keyring ───────────────────────────────────
echo "" | gnome-keyring-daemon --unlock || true

# ── Clean up stale lock files from unclean shutdowns ──────────────────────────
echo "[bridge] Cleaning up stale lock files..."
rm -f /root/.cache/protonmail/bridge-v3/bridge.lock \
      /root/.cache/protonmail/bridge-v3/bridge-gui.lock \
      2>/dev/null || true

# ── First-run: bootstrap GPG key + pass store ─────────────────────────────────
if [ ! -d "/root/.password-store" ]; then
    echo "[bridge] First run detected — initializing credential store..."
    mkdir -p "$GNUPGHOME"
    chmod 700 "$GNUPGHOME"

    gpg --batch --gen-key /protonmail/gpgparams

    KEY_FP=$(gpg --list-keys --with-colons | grep '^fpr' | head -1 | cut -d: -f10)
    echo "[bridge] GPG fingerprint: $KEY_FP"

    pass init "$KEY_FP"
    echo "[bridge] Credential store ready"
fi

# ── Interactive login mode (run once manually to authenticate) ─────────────────
if [ "${1}" = "init" ]; then
    if [ ! -t 0 ] || [ ! -t 1 ]; then
        echo "[bridge] ERROR: init mode requires an interactive TTY."
        echo "[bridge] Run with: docker run --rm -it -v protonmail-data:/root <image> init"
        echo "[bridge] For Docker Compose service-based init, set stdin_open: true and tty: true."
        exit 2
    fi

    echo "[bridge] Starting interactive CLI for account setup..."
    exec /protonmail/proton-bridge --cli
fi

# ── Normal daemon mode ─────────────────────────────────────────────────────────
echo "[bridge] Starting Proton Mail Bridge daemon..."
exec /protonmail/proton-bridge --noninteractive