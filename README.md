# scrcpy-installer

Install or update [scrcpy](https://github.com/Genymobile/scrcpy) on any Linux distribution from the **official GitHub releases** — no compilation, no `snap`, no `flatpak`.

- Pulls the **latest** release automatically (or a specific version with `--version`)
- Uses the official **prebuilt x86_64 binary** (glibc) when available; falls back to your distribution's package manager on other architectures or musl systems (Alpine)
- Verifies the download with the official **SHA256** checksums
- **Idempotent**: re-running the command updates scrcpy to the newest release
- Installs `scrcpy` (and a bundled `adb` when you don't have one) so it works from anywhere in your terminal
- Can be run as a **normal user** (installs to `~/.local`) or **system-wide** (installs to `/usr/local`)

---

## Install (copy & paste)

```bash
curl -fsSL https://raw.githubusercontent.com/zonaro/scrcpy-installer/main/install.sh | bash
```

That's it. `scrcpy` ends up in `~/.local/bin` (added to your PATH in `~/.bashrc` / `~/.zshrc` / `~/.profile` if needed). Open a new terminal and run:

```bash
scrcpy --version
```

> To install system-wide instead (into `/usr/local`), prefix with `sudo`:
>
> ```bash
> curl -fsSL https://raw.githubusercontent.com/zonaro/scrcpy-installer/main/install.sh | sudo bash
> ```

---

## Update

Just run the same command again — it detects the installed version and upgrades scrcpy to the latest release:

```bash
curl -fsSL https://raw.githubusercontent.com/zonaro/scrcpy-installer/main/install.sh | bash
```

Or, if you installed with `sudo`:

```bash
curl -fsSL https://raw.githubusercontent.com/zonaro/scrcpy-installer/main/install.sh | sudo bash
```

---

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/zonaro/scrcpy-installer/main/install.sh | bash -s -- --uninstall
```

---

## Usage

Once installed, use scrcpy normally:

```bash
# USB device (plug in + enable USB debugging first)
scrcpy

# Wireless device at 192.168.1.10:5555
adb connect 192.168.1.10:5555
scrcpy
```

See `scrcpy --help` for all options (crop, recording, audio, OTG mode, ...).

---

## Options

| Option | Description |
|---|---|
| `--version <tag>` | Install a specific release (e.g. `--version v3.3.4`); default is `latest` |
| `--prefix <dir>` | Install into a custom prefix (default: `~/.local`, or `/usr/local` when root) |
| `--system` | Install system-wide into `/usr/local` (equivalent to running as root) |
| `--force` | Reinstall even if that version is already installed |
| `--no-deps` | Skip automatic dependency installation |
| `--no-checksum` | Skip SHA256 verification of the downloaded archive |
| `--uninstall` | Remove the scrcpy installed by this script |

Example with options:

```bash
curl -fsSL https://raw.githubusercontent.com/zonaro/scrcpy-installer/main/install.sh | bash -s -- --version v3.3.4
```

---

## How it works

1. Queries `Genymobile/scrcpy` latest release via the GitHub API
2. Downloads the official prebuilt archive `scrcpy-linux-x86_64-<version>.tar.gz` (or the requested version)
3. Verifies its SHA256 against the official `SHA256SUMS.txt`
4. Extracts it into `~/.local/lib/scrcpy` (or `/usr/local/lib/scrcpy`) and symlinks the `scrcpy` binary into your PATH
5. Installs the bundled `adb` next to it if you don't have one, and the man page
6. Removes the previous version, so updates never accumulate

The layout keeps `scrcpy`, `scrcpy-server`, `adb` and the icons together, so the binary finds everything it needs relative to itself.

## Requirements

- `curl` (or `wget`), `tar` and `sha256sum` — present on virtually every Linux system
- `libudev.so.1` — ships with systemd/eudev on all mainstream distros; the script tries to install it if missing
- The official prebuilt requires **glibc**: on musl systems (e.g. Alpine) the script installs from the package manager instead

## Supported platforms

| Architecture | Method |
|---|---|
| Linux x86_64 (glibc) | Official prebuilt (recommended, always up to date) |
| Linux aarch64/arm64 | Distribution package manager fallback |
| Linux x86_64 (musl/Alpine) | Distribution package manager fallback (`apk add scrcpy`) |
| Other architectures | Distribution package manager fallback, or [build from source](https://github.com/Genymobile/scrcpy/blob/master/INSTALL.md) |

## Troubleshooting

- **`scrcpy: command not found`** — restart your terminal, or run `export PATH="$HOME/.local/bin:$PATH"`. The installer adds this line to your shell profile automatically when needed.
- **`ERROR: Could not find any ADB device`** — enable USB debugging on the device, authorize the RSA fingerprint, and check `adb devices`. If no system `adb` exists, the installer ships the one bundled with scrcpy.
- **`error while loading shared libraries: libudev.so.1`** — install `libudev1` (Debian/Ubuntu), `systemd-libs` (Fedora) or `libudev1` (openSUSE).
- **Alpine** — the official prebuilt is glibc-only; the installer detects musl and uses `apk add scrcpy` instead.
- **Why not snap/flatpak?** — this installs the upstream binary directly, tracking official releases as soon as they're published.

## License

The installer script is MIT-licensed. scrcpy itself is Apache 2.0 — see the [Genymobile/scrcpy](https://github.com/Genymobile/scrcpy) repository.