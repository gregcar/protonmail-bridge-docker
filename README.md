# protonmail-bridge-docker

A self-maintained Docker image of [Proton Mail Bridge](https://github.com/ProtonMail/proton-bridge) built from source for **ARM64 (Raspberry Pi)**. Automatically built and pushed to GitHub Container Registry via GitHub Actions whenever a new commit is pushed.

Built for use with [paperless-ngx](https://github.com/paperless-ngx/paperless-ngx) on a Raspberry Pi, but works for any use case that needs headless Proton Mail IMAP/SMTP access in a container.

---

## Why this exists

Proton Mail Bridge has no official ARM64 Docker image. Community images exist but are unmaintained. This repo builds directly from the official Proton Bridge source on every push, so it always tracks the latest upstream code.

---

## Requirements

- Raspberry Pi running 64-bit OS (arm64)
- Docker + Docker Compose
- A **paid** Proton Mail plan (Mail Plus, Proton Unlimited, or Business) — Bridge does not work with free accounts

---

## How credentials work

You log in **once**. The bridge stores credentials in a `pass` password store backed by a GPG key, both of which live in the Docker volume mounted at `/root`. As long as that volume is not deleted, the bridge authenticates automatically on every restart — including after Pi reboots or image updates.

You only need to re-run the login (`init`) if you:
- Delete the volume
- Change your Proton Mail password
- Revoke bridge sessions from the Proton web UI

---

## Setup

### 1. Pull the image

```bash
docker pull ghcr.io/YOURUSER/protonmail-bridge-docker:latest
```

If the package is private, log in to GHCR first (one-time):
```bash
echo YOUR_GITHUB_PAT | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin
```
Create a PAT at: GitHub → Settings → Developer settings → Personal access tokens → with `read:packages` scope.

---

### 2. Log in to Proton Mail (one-time only)

```bash
docker run --rm -it \
  -v protonmail-data:/root \
  ghcr.io/YOURUSER/protonmail-bridge-docker:latest init
```

This drops you into the Proton Bridge interactive CLI. Run:

```
>>> login
```

Follow the prompts (email, password, 2FA if enabled). When done:

```
>>> info
```

**Copy the generated IMAP/SMTP password** — this is what your mail client or paperless-ngx uses. It is not your Proton account password.

```
>>> exit
```

---

### 3. Add to your docker-compose.yml

```yaml
services:

  protonmail-bridge:
    image: ghcr.io/domisko/protonmail-bridge-docker:latest
    container_name: protonmail-bridge
    restart: unless-stopped
    volumes:
      - protonmail-data:/root

  # If paperless-ngx is in the same compose file, no ports needed —
  # use the container name directly as the IMAP host.
  # Otherwise, expose locally:
  # ports:
  #   - "127.0.0.1:1025:25"
  #   - "127.0.0.1:1143:143"

volumes:
  protonmail-data:
```

Start it:

```bash
docker compose up -d
```

---

## Connecting paperless-ngx

In the paperless-ngx admin UI under **Mail Accounts**, configure:

| Setting       | Value                                      |
|---------------|--------------------------------------------|
| IMAP server   | `protonmail-bridge` (container name, if same compose file) |
| IMAP port     | `143`                                      |
| Username      | `yourname@proton.me`                       |
| Password      | The bridge-generated password from `info`  |
| Security      | STARTTLS                                   |

---

## Updating the image

Whenever you want to pick up a newer version of Proton Bridge upstream, just push a commit to `main` (even a README change). GitHub Actions will rebuild from the latest source and push a new `latest` tag to GHCR.

On the Pi, pull and restart:

```bash
docker compose pull
docker compose up -d
```

Your credentials in the volume are untouched by updates.

---

## Rebuilding locally on the Pi

If you want to build directly on the Pi instead of pulling from GHCR:

```bash
git clone https://github.com/YOURUSER/protonmail-bridge-docker.git
cd protonmail-bridge-docker
docker build -t protonmail-bridge:local .
```

Then replace the image name in your `docker-compose.yml` with `protonmail-bridge:local`.

---

## Troubleshooting

**Bridge exits immediately on startup**
Check the logs: `docker logs protonmail-bridge`. Most commonly caused by a missing or corrupted volume. Re-run the `init` step.

**paperless-ngx can't connect**
- Confirm the bridge container is running: `docker ps`
- Check that both containers are on the same Docker network (same compose file = automatic)
- Verify you're using the bridge-generated password, not your Proton account password
- Try `docker exec -it protonmail-bridge /protonmail/proton-bridge --cli` then `>>> info` to confirm credentials are still valid

**Need to re-authenticate**
```bash
docker run --rm -it \
  -v protonmail-data:/root \
  ghcr.io/YOURUSER/protonmail-bridge-docker:latest init
```

---

## How it's built

- Source: official [ProtonMail/proton-bridge](https://github.com/ProtonMail/proton-bridge) repository, cloned fresh on every build
- Build target: `make build-nogui` — compiles the bridge without any Qt/GUI dependencies
- One patch applied at build time: `internal/constants/constants.go` is modified to bind on `0.0.0.0` instead of `127.0.0.1`, so the bridge is reachable from other containers
- Multi-stage build: Go toolchain and source are discarded, only the compiled binary + runtime libs end up in the final image
- CI: GitHub Actions using a native `ubuntu-24.04-arm` runner (no QEMU emulation)

---

## License

GPL-3.0 — same as upstream [Proton Mail Bridge](https://github.com/ProtonMail/proton-bridge/blob/master/LICENSE).