# Cloudflare OS Local Setup and LAN Support

A temporary setup and compatibility script for running [Cloudflare OS](https://github.com/cloudflare/cloudflare-os) locally while upstream installation, Windows, documentation, and LAN-related issues remain unresolved.

> This is a stopgap. Once upstream handles Node.js installation, pnpm versioning, local-server port handling, and LAN binding, this repository may no longer be needed.

## Why this repository exists

Cloudflare OS's upstream quick start assumes that Node.js and the correct pnpm version are already installed. It also does not currently cover LAN access or several first-run problems.

Relevant upstream issues include:

- [#15 — pnpm crash during initial run](https://github.com/cloudflare/cloudflare-os/issues/15)
- [#19 — pnpm run-local cannot start on Windows](https://github.com/cloudflare/cloudflare-os/issues/19)
- [#25 — Getting started documentation](https://github.com/cloudflare/cloudflare-os/issues/25)
- [#86 — local port and LAN URL handling](https://github.com/cloudflare/cloudflare-os/issues/86)

This repository provides a reproducible setup path while those issues are being addressed upstream.

## Setup script

`cloudflare-os-setup.sh` performs the following steps on a new Linux machine:

1. Installs Git using the available package manager (`apt`, `dnf`, `yum`, `pacman`, or Homebrew).
2. Installs Node.js v24.19.0 LTS under `~/.local/node` without requiring root access.
3. Installs pnpm 11.17.0, matching the version expected by the repository.
4. Clones or fast-forward updates the upstream `cloudflare/cloudflare-os` repository.
5. Applies the LAN patch to `run-dev-server.js` when needed.
6. Runs `pnpm install`.
7. Starts the local server with `pnpm run-local`.

### Usage

```bash
# Local-only mode
bash cloudflare-os-setup.sh

# Allow access from the local network
bash cloudflare-os-setup.sh --lan
```

The local-only server is available at `http://localhost:8787`. In LAN mode, the script also prints the detected LAN address.

### Environment variables

| Variable | Default | Description |
| --- | --- | --- |
| `REPO_URL` | `https://github.com/cloudflare/cloudflare-os.git` | Repository to clone |
| `TARGET_DIR` | `~/cloudflare-os` | Local source directory |
| `NODE_VERSION` | `v24.19.0` | Node.js version |
| `PNPM_VERSION` | `11.17.0` | pnpm version |

If the script is executed from inside an existing Cloudflare OS checkout, it automatically uses the current repository instead of cloning another copy.

## LAN support

The upstream local server normally binds to localhost. That prevents other devices on the same network from connecting. Binding only to `0.0.0.0` is not sufficient by itself: gatekeeper OAuth redirects and generated resource URLs must also use an address reachable by the client device.

The patch adds these options to `run-dev-server.js`:

| Option | Description |
| --- | --- |
| `--lan` | Bind to `0.0.0.0` and automatically detect a non-loopback IPv4 address |
| `--ip <ip>` | Explicitly select the Wrangler bind address |
| `--public-url <origin>` | Override the origin used in generated gatekeeper URLs |

Examples:

```bash
pnpm run-local -- --lan
pnpm run-local -- --ip 0.0.0.0 --public-url http://192.168.1.5:8787
```

In LAN mode, gatekeeper configuration receives a URL such as:

```text
http://192.168.1.5:8787/gatekeeper/github
```

An explicitly configured `BASE_URL` in a gatekeeper configuration takes precedence.

### OAuth configuration

For OAuth-based gatekeepers, the OAuth application must allow a redirect URI that exactly matches the address used by the local server, for example:

```text
http://192.168.1.5:8787/gatekeeper/github/oauth
```

The exact route depends on the gatekeeper. Context Library, Scheduler, and MCP do not require OAuth application changes.

## Limitations

- The LAN patch is applied after cloning and is not currently part of upstream.
- If upstream changes `run-dev-server.js`, the patch may no longer apply automatically.
- The script targets Linux environments. Windows users should use WSL or apply the upstream Windows compatibility changes manually.
- This repository does not replace Cloudflare OS deployment documentation or production deployment tooling.

## License

This repository contains setup and compatibility tooling for Cloudflare OS. Refer to the upstream project for the licensing terms of Cloudflare OS itself.
