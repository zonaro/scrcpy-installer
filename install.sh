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
#
# Options:
#   --version <tag>   Install a specific release tag (default: latest)
#   --prefix <dir>    Install prefix (default: ~/.local or /usr/local when root)
#   --system          Install system-wide into /usr/local (requires root/sudo)
#   --force           Reinstall even if the version is already installed
#   --no-deps         Skip automatic dependency installation
#   --no-checksum     Skip SHA256 verification of the downloaded archive
#   --uninstall       Remove the scrcpy installed by this script
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

# ---------------------------------------------------------------- usage
usage() {
    sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
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
    if [ ! -d "$LIB_DIR" ] && [ ! -L "$BIN_DIR/scrcpy" ]; then
        warn "nothing installed by this script at $PREFIX"
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

# ---------------------------------------------------------------- up-to-date check
if [ "$FORCE" -eq 0 ] && [ -f "$LIB_DIR/VERSION" ] && [ "$(cat "$LIB_DIR/VERSION")" = "$VERSION" ] \
    && [ -x "$BIN_DIR/scrcpy" ]; then
    info "scrcpy $VERSION is already installed ($BIN_DIR/scrcpy) — nothing to do. Use --force to reinstall."
    exit 0
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
run_priv ln -sfn "$INSTALL_DIR/scrcpy" "$BIN_DIR/scrcpy"

# if no system adb exists, expose the adb bundled with the official package
if ! command -v adb >/dev/null 2>&1 && [ -x "$INSTALL_DIR/adb" ]; then
    run_priv ln -sfn "$INSTALL_DIR/adb" "$BIN_DIR/adb"
    info "no system adb found — installed the adb bundled with scrcpy ($BIN_DIR/adb)"
fi

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
    [ "$NO_DEPS" -eq 1 ] && warn "dependencies were skipped (--no-deps): make sure adb and libudev are available"
else
    die "installation failed: $BIN_DIR/scrcpy is missing"
fi