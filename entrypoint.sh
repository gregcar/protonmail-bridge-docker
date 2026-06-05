#!/bin/bash
set -e

export GNUPGHOME="/root/.gnupg"

# ── Start DBus session (required for keychain/secret service) ─────────────────
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    echo "[bridge] Starting DBus session..."
    eval $(dbus-launch --sh-syntax)
    export DBUS_SESSION_BUS_ADDRESS
fi

# ── Start secret service (gnome-keyring) ──────────────────────────────────────
eval $(gnome-keyring-daemon --start --components=secrets)
export GNOME_KEYRING_CONTROL

# ── Unlock/create the default login keyring ───────────────────────────────────
echo "" | gnome-keyring-daemon --unlock

# ── Clean up stale lock files from unclean shutdowns ──────────────────────────
rm -f /root/.cache/protonmail/bridge-v3/bridge.lock \
      /root/.cache/protonmail/bridge-v3/bridge-gui.lock

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
    echo "[bridge] Starting interactive CLI for account setup..."
    exec /protonmail/bridge --cli
fi

# ── Normal daemon mode ─────────────────────────────────────────────────────────
echo "[bridge] Starting Proton Mail Bridge daemon..."
exec /protonmail/bridge --noninteractive
EOF