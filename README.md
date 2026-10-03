# scrcpy-installer

Install or update [scrcpy](https://github.com/Genymobile/scrcpy) on any Linux distribution **or Windows** from the **official GitHub releases** — no compilation, no `snap`, no `flatpak`, no `winget` lag.

- Pulls the **latest** release automatically (or a specific version with `--version` / `-Version`)
- Linux: uses the official **prebuilt x86_64 binary** (glibc) when available; falls back to your distribution's package manager on other architectures or musl systems (Alpine)
- Windows: uses the official **prebuilt `scrcpy-win64` / `scrcpy-win32` zip** (both arches covered, no fallback needed)
- Verifies the download with the official **SHA256** checksums
- **Idempotent**: re-running the command updates scrcpy to the newest release (asks for confirmation first when an older version is installed; `--force` / `-Force` skips the prompt)
- The `scrcpy` command shortcut is **always recreated**, even when the version is already up to date
- Optional **shortcuts** per device, with baked-in `scrcpy` arguments and a recolored icon: `.desktop` + custom SVG icon on Linux, `.lnk` (Start Menu) + custom `.ico` on Windows
- Can be run as a **normal user** (Linux: `~/.local`; Windows: `%LOCALAPPDATA%\scrcpy`) or **system-wide** (Linux: `/usr/local`; Windows: `%ProgramFiles%\scrcpy`)

> Prefer the visual way? The [web generator](https://zonaro.github.io/scrcpy-installer/) builds the command for you (Linux + Windows, PT-BR/EN/ES).

---

## Install (copy & paste)

```bash
curl -fsSL https://raw.githubusercontent.com/zonaro/scrcpy-installer/main/install.sh | bash
```

That's it. `scrcpy` ends up in `~/.local/bin` (added to your PATH in `~/.bashrc` / `~/.zshrc` / `~/.profile` if needed). Open a new terminal and run:

```bash
scrcpy --version
```

If a version is already installed, you'll be asked for confirmation before updating (when running interactively). When piped (non-TTY), it updates automatically. Pass `--force` to skip the prompt entirely. The `scrcpy` command shortcut is recreated on every run, even when nothing new is installed.

> To install system-wide instead (into `/usr/local`), prefix with `sudo`:
>
> ```bash
> curl -fsSL https://raw.githubusercontent.com/zonaro/scrcpy-installer/main/install.sh | sudo bash
> ```

---

## Update

Just run the same command again — it detects the installed version and upgrades scrcpy to the latest release. In an interactive terminal you'll be asked to confirm the update (`Y/n`, Enter accepts); when piped it proceeds automatically:

```bash
curl -fsSL https://raw.githubusercontent.com/zonaro/scrcpy-installer/main/install.sh | bash
```

Or, if you installed with `sudo`:

```bash
curl -fsSL https://raw.githubusercontent.com/zonaro/scrcpy-installer/main/install.sh | sudo bash
```

To update without being asked:

```bash
curl -fsSL https://raw.githubusercontent.com/zonaro/scrcpy-installer/main/install.sh | bash -s -- --force
```

---

## Windows (PowerShell)

Same behavior as Linux, via `install.ps1` — downloads the official `scrcpy-win64` (or `win32`) zip, verifies SHA256, extracts to `%LOCALAPPDATA%\scrcpy`, registers it on your user PATH, and optionally creates a Start Menu shortcut (`.lnk` pointing directly at `scrcpy.exe` with baked-in args and a custom `.ico` in your colors).

```powershell
Invoke-WebRequest -Uri https://raw.githubusercontent.com/zonaro/scrcpy-installer/main/install.ps1 -OutFile install.ps1
.\install.ps1
```

With a shortcut (equivalent of `--shortcut-name` + `--scrcpy-args`):

```powershell
.\install.ps1 -ShortcutName "Meu Celular" -ScrcpyArgs "--max-size 1024 --no-audio"
```

One-liner without touching disk:

```powershell
& ([scriptblock]::Create((Invoke-RestMethod https://raw.githubusercontent.com/zonaro/scrcpy-installer/main/install.ps1))) -ShortcutName "Meu Celular"
```

> System-wide instead (`%ProgramFiles%\scrcpy`): run PowerShell **as Administrator** and add `-System`. Uninstall: `.\install.ps1 -Uninstall` (add `-ShortcutName "Meu Celular"` to also remove that shortcut and its icons).

Parameter mapping: `--version → -Version`, `--prefix → -Prefix`, `--system → -System`, `--force → -Force`, `--no-checksum → -NoChecksum`, `--uninstall → -Uninstall`, `--shortcut-name → -ShortcutName`, `--scrcpy-args → -ScrcpyArgs`, `--icon-bg/fg/screen/eyes → -IconBg/-IconFg/-IconScreen/-IconEyes`, `--icon-url → -IconUrl`, `--shortcut-only → -ShortcutOnly` (`-NoDeps` is accepted as a no-op: the Windows prebuilt is self-contained).

---

## Desktop shortcut (Linux)

Create a launcher entry with a custom name, baked-in arguments and a recolored icon — handy when you have more than one phone:

```bash
curl -fsSL https://raw.githubusercontent.com/zonaro/scrcpy-installer/main/install.sh | bash -s -- --shortcut-name "Meu Celular" --scrcpy-args "--max-size 1024 --no-audio"
```

The shortcut is (re)written on every run of the installer, even when scrcpy itself is already up to date. Re-running with different colors or args updates the existing shortcut in place.

Icon colors are taken from the official scrcpy SVG and can be overridden:

```bash
curl -fsSL https://raw.githubusercontent.com/zonaro/scrcpy-installer/main/install.sh | bash -s -- \
  --shortcut-name "Work Phone" \
  --scrcpy-args "--max-size 1024" \
  --icon-bg "#0a3d62" --icon-fg "#60a3bc" --icon-screen "#f6e58d" --icon-eyes "#dfe6e9"
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
| `--force` | Update/reinstall without asking, even if scrcpy is already installed |
| `--no-deps` | Skip automatic dependency installation |
| `--no-checksum` | Skip SHA256 verification of the downloaded archive |
| `--uninstall` | Remove the scrcpy installed by this script |
| `--shortcut-name <name>` | Create/recreate a `.desktop` shortcut with this name |
| `--scrcpy-args "<args>"` | Arguments baked into the shortcut's `Exec=` line |
| `--icon-bg <hex>` | Recolor the icon background frame (default `#077063`) |
| `--icon-fg <hex>` | Recolor the icon body/antennas (default `#30dd81`) |
| `--icon-screen <hex>` | Recolor the icon lower screen (default `#e4e4e4`) |
| `--icon-eyes <hex>` | Recolor the icon eyes/white parts (default `#ffffff`) |
| `--icon-url <url>` | Custom SVG icon source (default: official `scrcpy.svg`) |
| `--shortcut-only` | Only create the shortcut, skip (re)installation (requires `--shortcut-name`) |

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
| Other Linux architectures | Distribution package manager fallback, or [build from source](https://github.com/Genymobile/scrcpy/blob/master/INSTALL.md) |
| Windows x64 | Official prebuilt `scrcpy-win64-*.zip` via `install.ps1` |
| Windows x86 (32-bit) | Official prebuilt `scrcpy-win32-*.zip` via `install.ps1` |

## Troubleshooting

- **`scrcpy: command not found`** — restart your terminal, or run `export PATH="$HOME/.local/bin:$PATH"`. The installer adds this line to your shell profile automatically when needed.
- **`ERROR: Could not find any ADB device`** — enable USB debugging on the device, authorize the RSA fingerprint, and check `adb devices`. If no system `adb` exists, the installer ships the one bundled with scrcpy.
- **`error while loading shared libraries: libudev.so.1`** — install `libudev1` (Debian/Ubuntu), `systemd-libs` (Fedora) or `libudev1` (openSUSE).
- **Alpine** — the official prebuilt is glibc-only; the installer detects musl and uses `apk add scrcpy` instead.
- **Why not snap/flatpak?** — this installs the upstream binary directly, tracking official releases as soon as they're published.

## License

The installer script is MIT-licensed. scrcpy itself is Apache 2.0 — see the [Genymobile/scrcpy](https://github.com/Genymobile/scrcpy) repository.