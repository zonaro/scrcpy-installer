#!/usr/bin/env bash
#
# scrcpy-installer
# Install or update scrcpy from the official Genymobile GitHub releases.
#
# Works on any Linux distribution:
#   - x86_64        -> downloads the official prebuilt binary (fast, no compilation)
#   - other archs   -> falls back to the distribution package manager
#   - Alpine/musl   -> falls back to the distribution package manager (prebuilts are glibc)
#
# Installs to ~/.local (user) by default, or /usr/local when run as root / with --system.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/zonaro/scrcpy-installer/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/zonaro/scrcpy-installer/main/install.sh | bash -s -- --shortcut-name "Meu Celular" --scrcpy-args "--max-size 1024 --no-audio"
#
# Options:
#   --version <tag>   Install a specific release tag (default: latest)
#   --prefix <dir>    Install prefix (default: ~/.local or /usr/local when root)
#   --system          Install system-wide into /usr/local (requires root/sudo)
#   --force           Update/reinstall without asking, even if a version is already installed
#   --no-deps         Skip automatic dependency installation
#   --no-checksum     Skip SHA256 verification of the downloaded archive
#   --uninstall       Remove the scrcpy installed by this script
#   --shortcut-name <name>  Create a .desktop shortcut with this name (uses --scrcpy-args as Exec args)
#   --scrcpy-args "<args>"  Arguments baked into the shortcut's Exec= line (default: "")
#   --icon-bg <hex>   Recolor SVG background frame (default: #077063)
#   --icon-fg <hex>   Recolor SVG body/antennas (default: #30dd81)
#   --icon-screen <hex>  Recolor SVG lower screen (default: #e4e4e4)
#   --icon-eyes <hex> Recolor SVG eyes/white parts (default: #ffffff)
#   --icon-url <url>  Custom SVG icon source (default: official scrcpy.svg)
#   --shortcut-only   Only create the shortcut, skip (re)installation (requires --shortcut-name)
#   --help            Show this help
#

set -euo pipefail

# ---------------------------------------------------------------- constants
REPO="Genymobile/scrcpy"
API_URL="https://api.github.com/repos/${REPO}/releases/latest"
BASE_URL="https://github.com/${REPO}/releases/download"

# ---------------------------------------------------------------- colors
if [ -t 1 ]; then
    C_RESET='\033[0m'; C_GREEN='\033[32m'; C_YELLOW='\033[33m'; C_RED='\033[31m'; C_CYAN='\033[36m'
else
    C_RESET=''; C_GREEN=''; C_YELLOW=''; C_RED=''; C_CYAN=''
fi

info()  { printf "${C_GREEN}[scrcpy]${C_RESET} %s\n" "$*"; }
warn()  { printf "${C_YELLOW}[scrcpy]${C_RESET} warning: %s\n" "$*" >&2; }
die()   { printf "${C_RED}[scrcpy]${C_RESET} error: %s\n" "$*" >&2; exit 1; }

# ---------------------------------------------------------------- defaults
VERSION=""
PREFIX=""
FORCE=0
NO_DEPS=0
NO_CHECKSUM=0
UNINSTALL=0
SHORTCUT_NAME=""
SCRCPY_ARGS=""
ICON_BG="#077063"
ICON_FG="#30dd81"
ICON_SCREEN="#e4e4e4"
ICON_EYES="#ffffff"
ICON_URL="https://github.com/Genymobile/scrcpy/raw/master/app/data/scrcpy.svg"
SHORTCUT_ONLY=0

TMP_DIR=""
cleanup() {
    # the trap's status would override the script's exit code otherwise
    [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ] && rm -rf "$TMP_DIR" || true
}
trap cleanup EXIT

# ---------------------------------------------------------------- helpers
# walk up from $1 until an existing directory is found, then test writability
can_write() {
    local d="$1"
    while [ -n "$d" ] && [ ! -d "$d" ]; do d="$(dirname "$d")"; done
    [ -n "$d" ] && [ -w "$d" ]
}

# use sudo only when the target prefix is not writable by the current user
run_priv() {
    if [ "$(id -u)" -eq 0 ]; then "$@"
    elif can_write "$PREFIX"; then "$@"
    else sudo "$@"; fi
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "missing required command: '$1' (install it first)"
}

detect_pm() {
    if   command -v apt-get  >/dev/null 2>&1; then echo "apt"
    elif command -v dnf      >/dev/null 2>&1; then echo "dnf"
    elif command -v pacman   >/dev/null 2>&1; then echo "pacman"
    elif command -v zypper   >/dev/null 2>&1; then echo "zypper"
    elif command -v apk      >/dev/null 2>&1; then echo "apk"
    elif command -v xbps-install >/dev/null 2>&1; then echo "xbps"
    elif command -v emerge   >/dev/null 2>&1; then echo "emerge"
    else echo "unknown"; fi
}

is_musl() {
    [ -e /lib/ld-musl-x86_64.so.1 ] || [ -e /lib/ld-musl-aarch64.so.1 ] \
        || (ldd --version 2>&1 || true) | grep -qi musl
}

is_glibc() { ! is_musl; }

pm_install() { # pm_install <package>
    local pkg="$1"
    case $(detect_pm) in
        apt)    run_priv apt-get update -qq >/dev/null 2>&1 || true
                run_priv apt-get install -y -qq "$pkg" ;;
        dnf)    run_priv dnf install -y "$pkg" ;;
        pacman) run_priv pacman -S --noconfirm --needed "$pkg" ;;
        zypper) run_priv zypper --non-interactive install "$pkg" ;;
        apk)    run_priv apk add --no-cache "$pkg" ;;
        xbps)   run_priv xbps-install -Sy "$pkg" ;;
        *)      return 1 ;;
    esac
}

download() { # download <url> <output-file>
    local url="$1" out="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --retry 3 --connect-timeout 10 -o "$out" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$out" "$url"
    else
        die "need 'curl' or 'wget' to download files"
    fi
}

sanitize_slug() { # sanitize_slug <name> -> safe filename slug
    printf '%s' "$1" \
        | tr '[:upper:]' '[:lower:]' \
        | sed -e 's/[ _]/-/g' -e 's/[^a-z0-9-]//g' -e 's/-\{2,\}/-/g' -e 's/^-//' -e 's/-$//'
}

create_shortcut() { # uses SHORTCUT_NAME, SCRCPY_ARGS, ICON_* globals
    local name="$SHORTCUT_NAME"
    [ -n "$name" ] || die "--shortcut-name requires a non-empty argument"
    local slug
    slug="$(sanitize_slug "$name")"
    [ -n "$slug" ] || slug="scrcpy"

    local bin
    if [ -x "$BIN_DIR/scrcpy" ]; then bin="$BIN_DIR/scrcpy"
    elif command -v scrcpy >/dev/null 2>&1; then bin="$(command -v scrcpy)"
    else bin="scrcpy"; fi

    local app_dir icon_dir
    if [ "$PREFIX" = "/usr/local" ] || [ "$(id -u)" -eq 0 ]; then
        app_dir="/usr/local/share/applications"
        icon_dir="/usr/local/share/icons"
    else
        app_dir="$HOME/.local/share/applications"
        icon_dir="$HOME/.local/share/icons"
    fi
    run_priv install -d "$app_dir" "$icon_dir"

    local icon_file="$icon_dir/$slug.svg"
    local desk_file="$app_dir/$slug.desktop"
    local changed=0

    # Each shortcut owns its icon ($slug.svg): only (re)write it when this
    # shortcut is new or its requested colors differ from what's on disk,
    # so other shortcuts' icons are never touched.
    info "checking icon $icon_file ..."
    if download "$ICON_URL" "$TMP_DIR/icon.svg"; then
        sed -e "s/#077063/${ICON_BG}/gI" \
            -e "s/#30dd81/${ICON_FG}/gI" \
            -e "s/#e4e4e4/${ICON_SCREEN}/gI" \
            -e "s/#ffffff/${ICON_EYES}/gI" \
            "$TMP_DIR/icon.svg" > "$TMP_DIR/icon-out.svg"
        if [ -f "$icon_file" ] && cmp -s "$TMP_DIR/icon-out.svg" "$icon_file"; then
            info "icon already up to date, keeping existing file"
        else
            run_priv install -m 644 "$TMP_DIR/icon-out.svg" "$icon_file"
            changed=1
            info "icon installed ($icon_file)"
        fi
    else
        warn "could not download icon from $ICON_URL; shortcut will use a generic icon"
        icon_file="video-display"
    fi

    local exec_line="$bin"
    [ -n "$SCRCPY_ARGS" ] && exec_line="$exec_line $SCRCPY_ARGS"

    {
        printf '[Desktop Entry]\n'
        printf 'Name=%s\n' "$name"
        printf 'Comment=scrcpy %s\n' "$SCRCPY_ARGS"
        printf 'Exec=%s\n' "$exec_line"
        printf 'Icon=%s\n' "$icon_file"
        printf 'Terminal=false\n'
        printf 'Type=Application\n'
        printf 'Categories=Utility;Video;\n'
        printf 'StartupWMClass=scrcpy\n'
        printf 'Keywords=scrcpy;android;mirror;\n'
    } > "$TMP_DIR/$slug.desktop"
    if [ -f "$desk_file" ] && cmp -s "$TMP_DIR/$slug.desktop" "$desk_file"; then
        info "shortcut already up to date ($desk_file)"
    else
        if [ -f "$desk_file" ]; then info "replacing existing shortcut $desk_file ..."
        else info "creating shortcut $desk_file ..."; fi
        run_priv install -m 644 "$TMP_DIR/$slug.desktop" "$desk_file"
        run_priv chmod +x "$desk_file" 2>/dev/null || true
        changed=1
    fi

    if [ "$changed" -eq 1 ] && command -v update-desktop-database >/dev/null 2>&1; then
        run_priv update-desktop-database -q "$app_dir" 2>/dev/null || true
    fi
    info "shortcut '$name' ready ($desk_file)"
}

# ---------------------------------------------------------------- usage
usage() {
    sed -n '1,/^[^#]/p' "$0" | sed 's/^# \{0,1\}//' | sed '1d;$d'
    exit 0
}

# ---------------------------------------------------------------- args
while [ $# -gt 0 ]; do
    case "$1" in
        --version)    VERSION="${2:?--version requires an argument}"; shift 2 ;;
        --prefix)     PREFIX="${2:?--prefix requires an argument}"; shift 2 ;;
        --system)     PREFIX="/usr/local"; shift ;;
        --force)      FORCE=1; shift ;;
        --no-deps)    NO_DEPS=1; shift ;;
        --no-checksum) NO_CHECKSUM=1; shift ;;
        --uninstall)  UNINSTALL=1; shift ;;
        --shortcut-name) SHORTCUT_NAME="${2:?--shortcut-name requires an argument}"; shift 2 ;;
        --scrcpy-args)  SCRCPY_ARGS="${2:?--scrcpy-args requires an argument}"; shift 2 ;;
        --icon-bg)    ICON_BG="${2:?--icon-bg requires an argument}"; shift 2 ;;
        --icon-fg)    ICON_FG="${2:?--icon-fg requires an argument}"; shift 2 ;;
        --icon-screen) ICON_SCREEN="${2:?--icon-screen requires an argument}"; shift 2 ;;
        --icon-eyes)  ICON_EYES="${2:?--icon-eyes requires an argument}"; shift 2 ;;
        --icon-url)   ICON_URL="${2:?--icon-url requires an argument}"; shift 2 ;;
        --shortcut-only) SHORTCUT_ONLY=1; shift ;;
        --help|-h)    usage ;;
        *) die "unknown option: $1 (see --help)" ;;
    esac
done

# ---------------------------------------------------------------- prefix / layout
if [ -z "$PREFIX" ]; then
    if [ "$(id -u)" -eq 0 ]; then PREFIX="/usr/local"; else PREFIX="$HOME/.local"; fi
fi

BIN_DIR="$PREFIX/bin"
LIB_DIR="$PREFIX/lib/scrcpy"
MAN_DIR="$PREFIX/share/man/man1"

# ---------------------------------------------------------------- uninstall
if [ "$UNINSTALL" -eq 1 ]; then
    if [ -n "$SHORTCUT_NAME" ]; then
        slug="$(sanitize_slug "$SHORTCUT_NAME")"
        [ -n "$slug" ] || slug="scrcpy"
        for d in "$HOME/.local/share/applications" "/usr/local/share/applications"; do
            [ -f "$d/$slug.desktop" ] && run_priv rm -f "$d/$slug.desktop" && info "removed shortcut $d/$slug.desktop"
        done
        for d in "$HOME/.local/share/icons" "/usr/local/share/icons"; do
            [ -f "$d/$slug.svg" ] && run_priv rm -f "$d/$slug.svg" && info "removed icon $d/$slug.svg"
        done
    fi
    if [ ! -d "$LIB_DIR" ] && [ ! -L "$BIN_DIR/scrcpy" ]; then
        warn "nothing installed by this script at $PREFIX"
        [ -n "$SHORTCUT_NAME" ] && exit 0
        exit 0
    fi
    run_priv rm -f  "$BIN_DIR/scrcpy"
    run_priv rm -f  "$BIN_DIR/adb"
    run_priv rm -f  "$MAN_DIR/scrcpy.1"
    run_priv rm -rf "$LIB_DIR"
    info "scrcpy uninstalled from $PREFIX"
    info "note: PATH entries added to your shell profiles were left untouched"
    exit 0
fi

# ---------------------------------------------------------------- shortcut-only (no install)
if [ "$SHORTCUT_ONLY" -eq 1 ]; then
    [ -n "$SHORTCUT_NAME" ] || die "--shortcut-only requires --shortcut-name <name>"
    TMP_DIR="$(mktemp -d)"
    create_shortcut
    exit 0
fi

# ---------------------------------------------------------------- arch detection
ARCH="$(uname -m)"
case "$ARCH" in
    x86_64)              ASSET_ARCH="x86_64" ;;
    aarch64|arm64)       ASSET_ARCH="aarch64" ;;
    *)                   ASSET_ARCH="" ;;
esac

# ---------------------------------------------------------------- musl / non-prebuilt handling
if [ "$ASSET_ARCH" != "x86_64" ] || is_musl; then
    [ "$ASSET_ARCH" = "x86_64" ] && is_musl \
        && warn "musl-based system (Alpine?): the official prebuilt is glibc-only; using the package manager instead"

    [ -n "$ASSET_ARCH" ] || warn "architecture '$ARCH' has no official prebuilt binary; using the package manager"

    if ! is_glibc || [ "$ASSET_ARCH" != "x86_64" ]; then
        info "installing scrcpy via the distribution package manager..."
        if ! pm_install "scrcpy"; then
            die "could not install scrcpy via package manager. Try your distro docs or build from source: https://github.com/Genymobile/scrcpy/blob/master/INSTALL.md"
        fi
        info "scrcpy installed via package manager. Verify with: scrcpy --version"
        exit 0
    fi
fi

require_command tar
require_command sha256sum

# ---------------------------------------------------------------- resolve version + asset
if [ -z "$VERSION" ]; then
    info "querying latest release from GitHub..."
    json="$(download "$API_URL" /dev/stdout 2>/dev/null || true)"
    VERSION="$(printf '%s\n' "$json" | grep -oE '"tag_name": *"[^"]+"' | head -n1 | sed -E 's/.*"([^"]+)"/\1/')"
    [ -n "$VERSION" ] || die "could not determine the latest release tag from $API_URL"
    ASSET_URL="$(printf '%s\n' "$json" | grep -oE '"browser_download_url": *"https://[^"]*scrcpy-linux-x86_64-[^"]*\.tar\.gz"' | head -n1 | sed -E 's/.*"(https[^"]+)"/\1/')"
    [ -n "$ASSET_URL" ] || die "no linux x86_64 prebuilt asset found for latest release $VERSION"
else
    case "$VERSION" in v*) ;; *) VERSION="v$VERSION" ;; esac
    ASSET_URL="$BASE_URL/$VERSION/scrcpy-linux-x86_64-$VERSION.tar.gz"
fi

ASSET_NAME="${ASSET_URL##*/}"
INSTALL_DIR="$LIB_DIR/$VERSION"

# ---------------------------------------------------------------- installed state
INSTALLED_VERSION=""
[ -f "$LIB_DIR/VERSION" ] && INSTALLED_VERSION="$(cat "$LIB_DIR/VERSION")"

# always (re)create the scrcpy/adb bin shortcuts, even when nothing new is installed
refresh_shortcut() {
    [ -d "$BIN_DIR" ] || run_priv install -d "$BIN_DIR"
    run_priv ln -sfn "$INSTALL_DIR/scrcpy" "$BIN_DIR/scrcpy"
    if ! command -v adb >/dev/null 2>&1 && [ -x "$INSTALL_DIR/adb" ]; then
        run_priv ln -sfn "$INSTALL_DIR/adb" "$BIN_DIR/adb"
        info "no system adb found — installed the adb bundled with scrcpy ($BIN_DIR/adb)"
    fi
}

# ---------------------------------------------------------------- up-to-date: refresh shortcuts only
if [ -n "$INSTALLED_VERSION" ] && [ "$INSTALLED_VERSION" = "$VERSION" ] && [ -d "$LIB_DIR/$VERSION" ]; then
    refresh_shortcut
    if [ "$FORCE" -eq 0 ]; then
        info "scrcpy $VERSION is already installed — recreated the 'scrcpy' command shortcut. Use --force to reinstall."
        if [ -n "$SHORTCUT_NAME" ]; then
            TMP_DIR="$(mktemp -d)"
            create_shortcut
        fi
        exit 0
    fi
fi

# ---------------------------------------------------------------- update confirmation
if [ -n "$INSTALLED_VERSION" ] && [ "$INSTALLED_VERSION" != "$VERSION" ] && [ "$FORCE" -eq 0 ]; then
    if [ -t 0 ]; then
        printf "${C_CYAN}[scrcpy]${C_RESET} scrcpy %s is installed. Install %s instead? [Y/n] " "$INSTALLED_VERSION" "$VERSION"
        read -r REPLY || REPLY=""
        case "$REPLY" in
            ""|y|Y|yes|Yes|YES|s|S|sim|Sim|SIM) ;;
            *)
                info "cancelled — keeping scrcpy $INSTALLED_VERSION (use --force to update without asking)"
                if [ -n "$SHORTCUT_NAME" ]; then
                    TMP_DIR="$(mktemp -d)"
                    create_shortcut
                fi
                exit 0
                ;;
        esac
    else
        warn "scrcpy $INSTALLED_VERSION is installed; stdin is not a terminal, updating to $VERSION automatically (use --force to skip the prompt)"
    fi
fi

# ---------------------------------------------------------------- dependencies (best effort)
if [ "$NO_DEPS" -eq 0 ]; then
    # libudev is the only runtime dependency of the prebuilt binary
    if ! ldconfig -p 2>/dev/null | grep -q 'libudev\.so\.1'; then
        warn "libudev.so.1 not found; scrcpy needs it to run"
        case $(detect_pm) in
            apt)    pm_install libudev1 || true ;;
            dnf)    pm_install systemd-libs || true ;;
            zypper) pm_install libudev1 || true ;;
            *)      warn "install libudev manually if scrcpy fails to start" ;;
        esac
    fi

    # scrcpy v5.0 decodes video in hardware by default and silently falls back
    # to software when no driver is available, so a VA-API driver is a
    # nice-to-have, never a requirement
    vaapi="unknown"
    if [ ! -e /dev/dri/renderD128 ]; then
        vaapi="no"
    elif ! command -v vainfo >/dev/null 2>&1; then
        # on Wayland this node exists even with no VA-API driver installed, so
        # it is only a hint; without vainfo we cannot confirm anything
        vaapi="unknown"
    elif vainfo >/dev/null 2>&1; then
        vaapi="yes"
    else
        vaapi="no"
    fi

    case "$vaapi" in
        yes) info "hardware decoding: VA-API driver detected" ;;
        no)
            info "no VA-API driver found; scrcpy v5.0 will decode in software"
            case $(detect_pm) in
                apt)    pm_install mesa-va-drivers || true ;;
                dnf)    pm_install mesa-va-drivers || pm_install intel-media-driver || true ;;
                pacman) pm_install mesa || true ;;
                *)      warn "no known VA-API driver package for your distro — see your GPU vendor docs" ;;
            esac
            ;;
        *)  warn "could not confirm a VA-API driver; scrcpy v5.0 falls back to software decoding on its own" ;;
    esac
    info "force software decoding any time with: scrcpy --hwdec=disabled"
fi

# ---------------------------------------------------------------- download + checksum
[ -d "$LIB_DIR" ] || run_priv install -d "$LIB_DIR"
[ -d "$BIN_DIR" ] || run_priv install -d "$BIN_DIR"

TMP_DIR="$(mktemp -d)"
info "downloading $ASSET_NAME ..."
download "$ASSET_URL" "$TMP_DIR/$ASSET_NAME"

if [ "$NO_CHECKSUM" -eq 0 ]; then
    info "verifying SHA256 checksum..."
    download "$BASE_URL/$VERSION/SHA256SUMS.txt" "$TMP_DIR/SHA256SUMS.txt" \
        || warn "checksum file unavailable; skipping verification"
    if [ -f "$TMP_DIR/SHA256SUMS.txt" ]; then
        if (cd "$TMP_DIR" && grep -F "$ASSET_NAME" SHA256SUMS.txt | sha256sum -c --status 2>/dev/null); then
            info "checksum OK"
        else
            die "SHA256 verification FAILED for $ASSET_NAME (aborting for safety). Use --no-checksum to skip."
        fi
    fi
fi

# ---------------------------------------------------------------- extract
info "installing to $INSTALL_DIR ..."
run_priv mkdir -p "$INSTALL_DIR"
run_priv tar xzf "$TMP_DIR/$ASSET_NAME" -C "$INSTALL_DIR" --strip-components=1
run_priv chmod +x "$INSTALL_DIR/scrcpy" "$INSTALL_DIR/scrcpy-server" 2>/dev/null || true

# ---------------------------------------------------------------- man page
if [ -f "$INSTALL_DIR/scrcpy.1" ]; then
    run_priv install -d "$MAN_DIR"
    run_priv install -m 644 "$INSTALL_DIR/scrcpy.1" "$MAN_DIR/scrcpy.1"
fi

# ---------------------------------------------------------------- symlinks
refresh_shortcut

# ---------------------------------------------------------------- cleanup old version
OLD_VERSION=""
[ -f "$LIB_DIR/VERSION" ] && OLD_VERSION="$(cat "$LIB_DIR/VERSION")"
if [ -n "$OLD_VERSION" ] && [ "$OLD_VERSION" != "$VERSION" ] && [ -d "$LIB_DIR/$OLD_VERSION" ]; then
    run_priv rm -rf "$LIB_DIR/$OLD_VERSION"
    info "removed previous version $OLD_VERSION"
fi
run_priv sh -c "printf '%s\n' '$VERSION' > '$LIB_DIR/VERSION'"

# ---------------------------------------------------------------- PATH (user installs)
if [ "$PREFIX" = "$HOME/.local" ] && [ "$(id -u)" -ne 0 ]; then
    if ! command -v scrcpy >/dev/null 2>&1 && ! printf '%s' "$PATH" | grep -q "$HOME/.local/bin"; then
        PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'
        for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
            [ -f "$rc" ] || continue
            grep -qF "$PATH_LINE" "$rc" && continue
            printf '\n# added by scrcpy-installer\n%s\n' "$PATH_LINE" >> "$rc"
            info "added ~/.local/bin to PATH in $rc (open a new terminal)"
        done
        warn "~/.local/bin is not on your PATH yet — restart your terminal or run: export PATH=\"\$HOME/.local/bin:\$PATH\""
    fi
fi

# ---------------------------------------------------------------- verify
if [ -x "$BIN_DIR/scrcpy" ]; then
    "$BIN_DIR/scrcpy" --version
    info "${C_CYAN}scrcpy $VERSION installed successfully.${C_RESET}"
    [ "$NO_DEPS" -eq 1 ] && warn "dependencies were skipped (--no-deps): make sure adb and libudev are available (a VA-API driver is optional)"
else
    die "installation failed: $BIN_DIR/scrcpy is missing"
fi

# ---------------------------------------------------------------- optional shortcut
if [ -n "$SHORTCUT_NAME" ]; then
    create_shortcut
fi