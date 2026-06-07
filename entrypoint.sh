#!/bin/bash
set -e

export GNUPGHOME="/root/.gnupg"

# ── Network diagnostics (catch DNS/connectivity early) ────────────────────────
echo "[bridge] Checking network connectivity..."
if ! timeout 5 curl -s -I "https://proton.me/download/bridge/linux/x86/v1/version.json" > /dev/null 2>&1; then
    echo "[bridge] WARNING: Cannot reach proton.me. Checking DNS..."
    if ! timeout 2 nslookup proton.me > /dev/null 2>&1; then
        echo "[bridge] ERROR: DNS resolution failed. Check container network."
    else
        echo "[bridge] WARNING: DNS works but proton.me is unreachable. Network may be down or restricted."
    fi
fi

# ── Start DBus session with timeout (required for keychain/secret service) ────
# Skip DBus/keyring setup for init mode - not needed for credential entry
if [ "${1}" != "init" ]; then
    if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
        echo "[bridge] Starting DBus session..."
        DBUS_OUTPUT=$(timeout 5 dbus-launch --sh-syntax 2>/dev/null || echo "")
        if [ -z "$DBUS_OUTPUT" ]; then
            echo "[bridge] WARNING: dbus-launch timed out or failed. Continuing without explicit DBus session."
            # Try to start minimal DBus in background as fallback
            dbus-daemon --session --print-address --fork 2>/dev/null &
            sleep 1
        else
            eval "$DBUS_OUTPUT"
        fi
        export DBUS_SESSION_BUS_ADDRESS
    fi

    # ── Start secret service (gnome-keyring) with timeout ────────────────────────
    echo "[bridge] Starting gnome-keyring..."
    timeout 5 gnome-keyring-daemon --start --components=secrets > /tmp/gnome-keyring-env 2>&1 || {
        echo "[bridge] WARNING: gnome-keyring startup timed out. Continuing anyway."
    }
    if [ -f /tmp/gnome-keyring-env ]; then
        eval $(cat /tmp/gnome-keyring-env)
    fi
    export GNOME_KEYRING_CONTROL

    # ── Unlock/create the default login keyring with timeout ──────────────────────
    echo "[bridge] Unlocking keyring..."
    timeout 5 bash -c 'echo "" | gnome-keyring-daemon --unlock' || {
        echo "[bridge] WARNING: Keyring unlock timed out. Continuing anyway."
    }
else
    echo "[bridge] Init mode: skipping DBus/keyring setup (not needed for credential entry)"
fi

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

    if ! gpg --batch --gen-key /protonmail/gpgparams 2>/dev/null; then
        echo "[bridge] WARNING: GPG key generation had issues, but continuing..."
    fi

    KEY_FP=$(gpg --list-keys --with-colons 2>/dev/null | grep '^fpr' | head -1 | cut -d: -f10)
    if [ -z "$KEY_FP" ]; then
        echo "[bridge] ERROR: Could not retrieve GPG fingerprint. Bridge init may fail."
    else
        echo "[bridge] GPG fingerprint: $KEY_FP"
        if ! pass init "$KEY_FP" 2>/dev/null; then
            echo "[bridge] WARNING: pass init had issues, but continuing..."
        else
            echo "[bridge] Credential store ready"
        fi
    fi
fi

# ── Interactive login mode (run once manually to authenticate) ─────────────────
if [ "${1}" = "init" ]; then
    echo "[bridge] Starting interactive CLI for account setup..."
    echo "[bridge] If the Bridge appears to hang, try: docker logs -f protonmail-bridge"
    # Run Bridge with network timeout increased and version check disabled
    # The version check times out in containers; we disable it for init mode
    export PROTON_BRIDGE_SKIP_VERSION_CHECK=1
    exec timeout 600 /protonmail/bridge --cli || {
        EXIT_CODE=$?
        if [ $EXIT_CODE -eq 124 ]; then
            echo "[bridge] ERROR: Bridge CLI timed out after 10 minutes."
        fi
        exit $EXIT_CODE
    }
fi

# ── Normal daemon mode ─────────────────────────────────────────────────────────
echo "[bridge] Starting Proton Mail Bridge daemon..."
exec /protonmail/bridge --noninteractive