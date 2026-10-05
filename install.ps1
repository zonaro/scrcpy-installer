<#
.SYNOPSIS
  scrcpy-installer (Windows) - install or update scrcpy from official Genymobile GitHub releases.

.DESCRIPTION
  PowerShell port of install.sh. Works on Windows 10/11 (64-bit and 32-bit):
    - 64-bit OS -> downloads the official prebuilt scrcpy-win64-<version>.zip
    - 32-bit OS -> downloads the official prebuilt scrcpy-win32-<version>.zip

  Installs per-user into %LOCALAPPDATA%\scrcpy by default, or %ProgramFiles%\scrcpy
  with -System (requires elevation).

  Instead of a Linux .desktop entry, every shortcut is a single .lnk:
    <slug>.lnk  (Start Menu shortcut pointing directly at scrcpy.exe,
                 with baked-in arguments and the custom .ico)

  The icon is the official scrcpy.svg, recolored (bg/fg/screen/eyes) and saved as
  <slug>.svg, plus a <slug>.ico generated with the same colors for the .lnk.

.EXAMPLE
  # install latest (per-user)
  .\install.ps1

.EXAMPLE
  # install + Start Menu shortcut with baked-in args
  .\install.ps1 -ShortcutName "Meu Celular" -ScrcpyArgs "--max-size 1024 --no-audio"

.EXAMPLE
  # one-liner (download + run)
  Invoke-WebRequest -Uri https://raw.githubusercontent.com/zonaro/scrcpy-installer/main/install.ps1 -OutFile install.ps1
  .\install.ps1 -ShortcutName "Meu Celular" -ScrcpyArgs "--max-size 1024 --no-audio"

.EXAMPLE
  # one-liner without touching disk (PowerShell 5.1+)
  & ([scriptblock]::Create((Invoke-RestMethod https://raw.githubusercontent.com/zonaro/scrcpy-installer/main/install.ps1))) -ShortcutName "Meu Celular"

.PARAMETER Version
  Install a specific release tag (default: latest). Accepts "v3.3.4" or "3.3.4".

.PARAMETER Prefix
  Install prefix (default: %LOCALAPPDATA%\scrcpy, or %ProgramFiles%\scrcpy with -System).

.PARAMETER System
  Install system-wide into %ProgramFiles%\scrcpy (requires elevation).

.PARAMETER Force
  Update/reinstall without asking, even if the version is already installed.

.PARAMETER NoDeps
  Accepted for parity with install.sh. The Windows prebuilt has no extra
  runtime dependencies, so this is a no-op.

.PARAMETER NoChecksum
  Skip SHA256 verification of the downloaded archive.

.PARAMETER Uninstall
  Remove the scrcpy installed by this script. Combine with -ShortcutName to
  also remove that shortcut (.lnk) and its icons.

.PARAMETER ShortcutName
  Create a Start Menu shortcut (.lnk) with this name
  (uses -ScrcpyArgs as baked-in arguments).

.PARAMETER ScrcpyArgs
  Arguments baked into the shortcut's Arguments field (default: "").

.PARAMETER IconBg
  Recolor SVG background frame (default: #077063).

.PARAMETER IconFg
  Recolor SVG body/antennas (default: #30dd81).

.PARAMETER IconScreen
  Recolor SVG lower screen (default: #e4e4e4).

.PARAMETER IconEyes
  Recolor SVG eyes/white parts (default: #ffffff).

.PARAMETER IconUrl
  Custom SVG icon source (default: official scrcpy.svg).

.PARAMETER ShortcutOnly
  Only create the shortcut, skip (re)installation (requires -ShortcutName).

.PARAMETER Help
  Show this help.
#>
[CmdletBinding()]
param(
  [string]$Version = "",
  [string]$Prefix = "",
  [switch]$System,
  [switch]$Force,
  [switch]$NoDeps,
  [switch]$NoChecksum,
  [switch]$Uninstall,
  [string]$ShortcutName = "",
  [string]$ScrcpyArgs = "",
  [string]$IconBg = "#077063",
  [string]$IconFg = "#30dd81",
  [string]$IconScreen = "#e4e4e4",
  [string]$IconEyes = "#ffffff",
  [string]$IconUrl = "https://github.com/Genymobile/scrcpy/raw/master/app/data/scrcpy.svg",
  [switch]$ShortcutOnly,
  [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------- constants
$Repo = "Genymobile/scrcpy"
$ApiUrl = "https://api.github.com/repos/$Repo/releases/latest"
$BaseUrl = "https://github.com/$Repo/releases/download"

# ---------------------------------------------------------------- helpers
function Write-Info($msg) { Write-Host "[scrcpy] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Warning "[scrcpy] $msg" }
function Fail($msg) { Write-Host "[scrcpy] error: $msg" -ForegroundColor Red; exit 1 }

function Test-IsAdmin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p = New-Object Security.Principal.WindowsPrincipal($id)
  return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-Slug([string]$name) {
  $s = $name.ToLowerInvariant().Normalize([Text.NormalizationForm]::FormD)
  $s = $s -replace '\p{Mn}', ''
  $s = $s -replace '[ _]+', '-'
  $s = $s -replace '[^a-z0-9-]', ''
  $s = $s -replace '-{2,}', '-'
  $s = $s.Trim('-')
  if ([string]::IsNullOrEmpty($s)) { $s = "scrcpy" }
  return $s
}

function Get-ScrcpyExe {
  # Resolution order mirrors install.sh: installed version first, then PATH.
  if (-not [string]::IsNullOrWhiteSpace($InstallDir)) {
    $fromInstall = Join-Path $InstallDir "scrcpy.exe"
    if (Test-Path $fromInstall) { return $fromInstall }
  }
  $cmd = Get-Command "scrcpy.exe" -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $cmd2 = Get-Command "scrcpy" -ErrorAction SilentlyContinue
  if ($cmd2) { return $cmd2.Source }
  return "scrcpy.exe"
}

function Add-ToPathOnce([string]$dir, [switch]$Machine) {
  $scope = "User"
  if ($Machine) { $scope = "Machine" }
  $current = [Environment]::GetEnvironmentVariable("Path", $scope)
  if ([string]::IsNullOrEmpty($current)) { $current = "" }
  $parts = $current -split ';' | Where-Object { $_ -and $_.TrimEnd('\') -ne $dir.TrimEnd('\') }
  $parts = @($parts) + @($dir)
  $newPath = ($parts -join ';')
  [Environment]::SetEnvironmentVariable("Path", $newPath, $scope)
  if (($env:Path -split ';' | Where-Object { $_.TrimEnd('\') -eq $dir.TrimEnd('\') }).Count -eq 0) {
    $env:Path = "$env:Path;$dir"
  }
  Write-Info "added $dir to $scope PATH (open a new terminal)"
}

function Remove-FromPath([string]$dir, [switch]$Machine) {
  $scope = "User"
  if ($Machine) { $scope = "Machine" }
  $current = [Environment]::GetEnvironmentVariable("Path", $scope)
  if ([string]::IsNullOrEmpty($current)) { return }
  $parts = $current -split ';' | Where-Object { $_ -and $_.TrimEnd('\') -ne $dir.TrimEnd('\') }
  [Environment]::SetEnvironmentVariable("Path", ($parts -join ';'), $scope)
}

# Remove any stale PATH entry pointing at a previous version of our lib dir.
function Remove-StaleLibPaths([switch]$Machine) {
  $scope = "User"
  if ($Machine) { $scope = "Machine" }
  $current = [Environment]::GetEnvironmentVariable("Path", $scope)
  if ([string]::IsNullOrEmpty($current)) { return }
  $libRoot = $LibDir.TrimEnd('\')
  $parts = $current -split ';' | Where-Object {
    $_ -and -not ($_.TrimEnd('\') -eq $libRoot -or $_.TrimEnd('\').StartsWith($libRoot + '\', [StringComparison]::OrdinalIgnoreCase))
  }
  $newPath = ($parts -join ';')
  if ($newPath -ne $current) {
    [Environment]::SetEnvironmentVariable("Path", $newPath, $scope)
  }
}

function New-CustomIco([string]$icoPath, [string]$bg, [string]$fg, [string]$screen, [string]$eyes) {
  # Pure-GDI+ icon honoring the 4 custom colors: no external converter needed.
  # Layout mirrors the official scrcpy.svg: frame (bg), body+antennas (fg),
  # lower screen band (screen), two eyes (eyes). Shadows/highlights omitted.
  Add-Type -AssemblyName System.Drawing
  $size = 256
  $bmp = New-Object System.Drawing.Bitmap($size, $size)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  try {
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    $cBg = [System.Drawing.ColorTranslator]::FromHtml($bg)
    $cFg = [System.Drawing.ColorTranslator]::FromHtml($fg)
    $cScreen = [System.Drawing.ColorTranslator]::FromHtml($screen)
    $cEyes = [System.Drawing.ColorTranslator]::FromHtml($eyes)
    $bBg = New-Object System.Drawing.SolidBrush($cBg)
    $bFg = New-Object System.Drawing.SolidBrush($cFg)
    $bScreen = New-Object System.Drawing.SolidBrush($cScreen)
    $bEyes = New-Object System.Drawing.SolidBrush($cEyes)
    $pFg = New-Object System.Drawing.Pen($cFg, 14)
    $pFg.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pFg.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    try {
      # frame: rounded rect
      $frame = New-Object System.Drawing.Rectangle(24, 28, 208, 200)
      $path = New-Object System.Drawing.Drawing2D.GraphicsPath
      $r = 22
      $path.AddArc($frame.X, $frame.Y, $r * 2, $r * 2, 180, 90)
      $path.AddArc($frame.Right - $r * 2, $frame.Y, $r * 2, $r * 2, 270, 90)
      $path.AddArc($frame.Right - $r * 2, $frame.Bottom - $r * 2, $r * 2, $r * 2, 0, 90)
      $path.AddArc($frame.X, $frame.Bottom - $r * 2, $r * 2, $r * 2, 90, 90)
      $path.CloseFigure()
      $g.FillPath($bBg, $path)
      # antennas
      $g.DrawLine($pFg, 96, 108, 64, 62)
      $g.DrawLine($pFg, 160, 108, 192, 62)
      # body: ellipse
      $g.FillEllipse($bFg, 52, 96, 152, 96)
      # lower screen band
      $g.FillRectangle($bScreen, 24, 186, 208, 24)
      # eyes
      $g.FillEllipse($bEyes, 88, 128, 24, 24)
      $g.FillEllipse($bEyes, 144, 128, 24, 24)
    } finally {
      $bBg.Dispose(); $bFg.Dispose(); $bScreen.Dispose(); $bEyes.Dispose()
      $pFg.Dispose(); $path.Dispose()
    }
    # PNG-compressed single-image ICO (Vista+): ICONDIR + ICONDIRENTRY + PNG.
    $tmpPng = Join-Path ([IO.Path]::GetTempPath()) ("scrcpy-icon-" + [Guid]::NewGuid().ToString("N") + ".png")
    try {
      $bmp.Save($tmpPng, [System.Drawing.Imaging.ImageFormat]::Png)
      $png = [IO.File]::ReadAllBytes($tmpPng)
      $fs = [IO.File]::Create($icoPath)
      try {
        $bw = New-Object IO.BinaryWriter($fs)
        $bw.Write([UInt16]0); $bw.Write([UInt16]1); $bw.Write([UInt16]1)   # reserved, type, count
        $bw.Write([Byte]0)          # width (0 = 256)
        $bw.Write([Byte]0)          # height (0 = 256)
        $bw.Write([Byte]0)          # palette
        $bw.Write([Byte]0)          # reserved
        $bw.Write([UInt16]1)        # planes
        $bw.Write([UInt16]32)       # bitcount
        $bw.Write([UInt32]$png.Length)
        $bw.Write([UInt32]22)       # offset
        $bw.Write($png)
        $bw.Flush()
      } finally { $fs.Close() }
    } finally {
      if (Test-Path $tmpPng) { Remove-Item $tmpPng -Force }
    }
  } finally {
    $g.Dispose(); $bmp.Dispose()
  }
}

function New-Shortcut {
  # Mirrors create_shortcut() from install.sh: owns <slug>.lnk
  # and <slug>.svg + <slug>.ico, updating each only when content changed.
  # The execution command goes directly into the .lnk (TargetPath + Arguments),
  # no intermediate .bat launcher.
  if ([string]::IsNullOrWhiteSpace($ShortcutName)) { Fail "--ShortcutName requires a non-empty argument" }
  $name = $ShortcutName
  $slug = Get-Slug $name

  $exe = Get-ScrcpyExe

  if (-not (Test-Path $ShortcutDir)) { New-Item -ItemType Directory -Path $ShortcutDir -Force | Out-Null }
  if (-not (Test-Path $IconDir)) { New-Item -ItemType Directory -Path $IconDir -Force | Out-Null }

  $iconSvg = Join-Path $IconDir "${slug}.svg"
  $iconIco = Join-Path $IconDir "${slug}.ico"
  $lnkFile = Join-Path $ShortcutDir "${slug}.lnk"
  $legacyBat = Join-Path $ShortcutDir "${slug}.bat"
  $tmpSvg = Join-Path $TempDir "icon.svg"
  $tmpOut = Join-Path $TempDir "icon-out.svg"

  # Each shortcut owns its icon (<slug>.svg/.ico): only (re)write when new or
  # colors differ, so other shortcuts' icons are never touched.
  Write-Info "checking icon $iconSvg ..."
  try {
    Invoke-WebRequest -Uri $IconUrl -OutFile $tmpSvg -UseBasicParsing
    $svg = [IO.File]::ReadAllText($tmpSvg)
    $svg = $svg -replace '(?i)#077063', $IconBg
    $svg = $svg -replace '(?i)#30dd81', $IconFg
    $svg = $svg -replace '(?i)#e4e4e4', $IconScreen
    $svg = $svg -replace '(?i)#ffffff', $IconEyes
    [IO.File]::WriteAllText($tmpOut, $svg)
    $writeSvg = $true
    if (Test-Path $iconSvg) {
      $a = [IO.File]::ReadAllText($iconSvg); $b = [IO.File]::ReadAllText($tmpOut)
      if ($a -eq $b) { Write-Info "icon already up to date, keeping existing file"; $writeSvg = $false }
    }
    if ($writeSvg) {
      Copy-Item $tmpOut $iconSvg -Force
      Write-Info "icon installed ($iconSvg)"
    }
  } catch {
    Write-Warn "could not download icon from $IconUrl; shortcut will use scrcpy.exe's icon"
    $iconSvg = ""
  }

  # ICO for the .lnk (Windows shortcuts need .ico, not .svg).
  if ($iconSvg) {
    try {
      New-CustomIco $iconIco $IconBg $IconFg $IconScreen $IconEyes
      Write-Info "icon installed ($iconIco)"
    } catch {
      Write-Warn "could not generate custom .ico ($($_.Exception.Message)); shortcut will use scrcpy.exe's icon"
      $iconIco = ""
    }
  } else { $iconIco = "" }

  # Remove legacy .bat launcher from versions that used a .bat + .lnk pair.
  if (Test-Path $legacyBat) { Remove-Item $legacyBat -Force; Write-Info "removed legacy launcher $legacyBat" }

  # .lnk shortcut pointing directly at scrcpy.exe (equivalent of the .desktop Exec= line).
  $shell = New-Object -ComObject WScript.Shell
  $sc = $shell.CreateShortcut($lnkFile)
  $sc.TargetPath = $exe
  $sc.Arguments = $ScrcpyArgs.Trim()
  $exeDir = Split-Path $exe -Parent
  if ($exeDir) { $sc.WorkingDirectory = $exeDir }
  $sc.Description = "scrcpy $ScrcpyArgs".Trim()
  $sc.WindowStyle = 1
  if ($iconIco -and (Test-Path $iconIco)) { $sc.IconLocation = $iconIco }
  elseif ($exe -ne "scrcpy.exe" -and (Test-Path $exe)) { $sc.IconLocation = "$exe,0" }
  $sc.Save()
  Write-Info "shortcut '$name' ready ($lnkFile)"
}

# ---------------------------------------------------------------- help
if ($Help) {
  Get-Help $PSCommandPath -Detailed
  exit 0
}

# ---------------------------------------------------------------- prefix / layout
$IsAdmin = Test-IsAdmin
if ($System) {
  $Prefix = Join-Path $env:ProgramFiles "scrcpy"
  $UseMachineScope = $true
  if (-not $IsAdmin) {
    Fail "-System installs to $Prefix and needs elevation. Re-run PowerShell as Administrator."
  }
} else {
  $UseMachineScope = $false
  if ([string]::IsNullOrWhiteSpace($Prefix)) {
    # NOTE: unlike install.sh (root defaults to /usr/local), an elevated
    # Windows shell still defaults to the per-user prefix — %LOCALAPPDATA% is
    # always writable. Machine-wide install is opt-in via -System.
    $Prefix = Join-Path $env:LOCALAPPDATA "scrcpy"
  }
}

$LibDir = Join-Path $Prefix "lib\scrcpy"
$IconDir = Join-Path $Prefix "share\icons"
if ($UseMachineScope) {
  $ShortcutDir = Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs\scrcpy-installer"
} else {
  $ShortcutDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\scrcpy-installer"
}

$TempDir = Join-Path ([IO.Path]::GetTempPath()) ("scrcpy-install-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
try {
  # ---------------------------------------------------------------- uninstall
  if ($Uninstall) {
    if (-not [string]::IsNullOrWhiteSpace($ShortcutName)) {
      $slug = Get-Slug $ShortcutName
      foreach ($d in @($ShortcutDir)) {
        foreach ($f in @("$d\${slug}.lnk", "$d\${slug}.bat")) {
          if (Test-Path $f) { Remove-Item $f -Force; Write-Info "removed shortcut $f" }
        }
      }
      foreach ($d in @($IconDir)) {
        foreach ($f in @("$d\${slug}.svg", "$d\${slug}.ico")) {
          if (Test-Path $f) { Remove-Item $f -Force; Write-Info "removed icon $f" }
        }
      }
    }
    $versionFile = Join-Path $LibDir "VERSION"
    if ((-not (Test-Path $LibDir)) -and (-not [string]::IsNullOrWhiteSpace($ShortcutName))) { exit 0 }
    if (-not (Test-Path $LibDir)) { Write-Warn "nothing installed by this script at $Prefix"; exit 0 }
    if (Test-Path $versionFile) {
      $old = ([IO.File]::ReadAllText($versionFile)).Trim()
      if ($old) { Remove-FromPath (Join-Path $LibDir $old) -Machine:$UseMachineScope }
    }
    Remove-StaleLibPaths -Machine:$UseMachineScope
    Remove-Item $LibDir -Recurse -Force
    Write-Info "scrcpy uninstalled from $Prefix"
    Write-Info "note: Start Menu shortcuts not tied to -ShortcutName were left untouched"
    exit 0
  }

  # ---------------------------------------------------------------- shortcut-only (no install)
  if ($ShortcutOnly) {
    if ([string]::IsNullOrWhiteSpace($ShortcutName)) { Fail "-ShortcutOnly requires -ShortcutName <name>" }
    $InstallDir = ""
    New-Shortcut
    exit 0
  }

  # ---------------------------------------------------------------- arch detection
  function Get-ScrcpyVersionParts([string]$Tag) {
    if ($Tag -notmatch '^v?(\d+)(?:\.(\d+))?(?:\.(\d+))?') { return $null }
    $p = @($Matches[1], $Matches[2], $Matches[3]) | ForEach-Object { if ($_ -eq "") { 0 } else { [int]$_ } }
    return ,$p
  }

  # native ARM64 prebuilts only exist from scrcpy v5.0 on, so an older pinned
  # release has to fall back to win64; an unparseable tag is left alone
  function Test-ScrcpyVersionAtLeast([string]$Tag, [int]$Major, [int]$Minor) {
    $p = Get-ScrcpyVersionParts $Tag
    if (-not $p) { return $true }
    if ($p[0] -ne $Major) { return $p[0] -gt $Major }
    return $p[1] -ge $Minor
  }

  # an x64 PowerShell emulated on Windows ARM64 reports AMD64 here, and the real
  # architecture shows up in PROCESSOR_ARCHITEW6432 instead
  $nativeArch = $env:PROCESSOR_ARCHITEW6432
  if ([string]::IsNullOrWhiteSpace($nativeArch)) { $nativeArch = $env:PROCESSOR_ARCHITECTURE }
  if ($nativeArch -and ($nativeArch -ieq "ARM64")) { $AssetArch = "winarm64" }
  elseif ([Environment]::Is64BitOperatingSystem) { $AssetArch = "win64" }
  else { $AssetArch = "win32" }

  if (($AssetArch -eq "winarm64") -and -not [string]::IsNullOrWhiteSpace($Version) -and
      -not (Test-ScrcpyVersionAtLeast $Version 5 0)) {
    Write-Info "native ARM64 prebuilts start at scrcpy v5.0; using win64 for $Version"
    $AssetArch = "win64"
  }

  if ($NoDeps) { Write-Info "-NoDeps: nothing to skip on Windows (prebuilt is self-contained)" }

  # ---------------------------------------------------------------- resolve version + asset
  if ([string]::IsNullOrWhiteSpace($Version)) {
    Write-Info "querying latest release from GitHub..."
    $headers = @{ "User-Agent" = "scrcpy-installer-ps1" }
    $rel = Invoke-RestMethod -Uri $ApiUrl -Headers $headers
    $Version = $rel.tag_name
    if ([string]::IsNullOrWhiteSpace($Version)) { Fail "could not determine the latest release tag from $ApiUrl" }
    $asset = $rel.assets | Where-Object { $_.name -like "scrcpy-$AssetArch-*.zip" } | Select-Object -First 1
    if ((-not $asset) -and ($AssetArch -eq "winarm64")) {
      Write-Info "release $Version ships no winarm64 prebuilt; falling back to win64"
      $AssetArch = "win64"
      $asset = $rel.assets | Where-Object { $_.name -like "scrcpy-win64-*.zip" } | Select-Object -First 1
    }
    if (-not $asset) { Fail "no $AssetArch prebuilt asset found for latest release $Version" }
    $AssetUrl = $asset.browser_download_url
  } else {
    if ($Version -notlike "v*") { $Version = "v$Version" }
    $AssetUrl = "$BaseUrl/$Version/scrcpy-$AssetArch-${Version}.zip"
  }

  $AssetName = $AssetUrl.Substring($AssetUrl.LastIndexOf('/') + 1)
  $InstallDir = Join-Path $LibDir $Version

  # ---------------------------------------------------------------- installed state
  $InstalledVersion = ""
  $versionFile = Join-Path $LibDir "VERSION"
  if (Test-Path $versionFile) { $InstalledVersion = ([IO.File]::ReadAllText($versionFile)).Trim() }

  # always (re)register the install dir on PATH, even when nothing new is installed
  function Refresh-PathEntry {
    Remove-StaleLibPaths -Machine:$UseMachineScope
    Add-ToPathOnce $InstallDir -Machine:$UseMachineScope
  }

  # ---------------------------------------------------------------- up-to-date: refresh PATH only
  if ($InstalledVersion -and ($InstalledVersion -eq $Version) -and (Test-Path $InstallDir)) {
    Refresh-PathEntry
    if (-not $Force) {
      Write-Info "scrcpy $Version is already installed - PATH refreshed. Use -Force to reinstall."
      if (-not [string]::IsNullOrWhiteSpace($ShortcutName)) { New-Shortcut }
      exit 0
    }
  }

  # ---------------------------------------------------------------- update confirmation
  if ($InstalledVersion -and ($InstalledVersion -ne $Version) -and (-not $Force)) {
    $interactive = $false
    try { $interactive = [Environment]::UserInteractive -and ($null -ne $Host.UI.RawUI) -and (-not [Console]::IsInputRedirected) } catch { $interactive = $false }
    if ($interactive) {
      $reply = Read-Host "[scrcpy] scrcpy $InstalledVersion is installed. Install $Version instead? [Y/n]"
      if ($reply -match '^(|y|Y|yes|Yes|YES|s|S|sim|Sim|SIM)$') { }
      else {
        Write-Info "cancelled - keeping scrcpy $InstalledVersion (use -Force to update without asking)"
        if (-not [string]::IsNullOrWhiteSpace($ShortcutName)) { New-Shortcut }
        exit 0
      }
    } else {
      Write-Warn "scrcpy $InstalledVersion is installed; stdin is not a terminal, updating to $Version automatically (use -Force to skip the prompt)"
    }
  }

  # ---------------------------------------------------------------- download + checksum
  if (-not (Test-Path $LibDir)) { New-Item -ItemType Directory -Path $LibDir -Force | Out-Null }

  Write-Info "downloading $AssetName ..."
  $assetFile = Join-Path $TempDir $AssetName
  Invoke-WebRequest -Uri $AssetUrl -OutFile $assetFile -UseBasicParsing

  if (-not $NoChecksum) {
    Write-Info "verifying SHA256 checksum..."
    try {
      $sumsUrl = "$BaseUrl/$Version/SHA256SUMS.txt"
      $sumsFile = Join-Path $TempDir "SHA256SUMS.txt"
      Invoke-WebRequest -Uri $sumsUrl -OutFile $sumsFile -UseBasicParsing
      $line = Get-Content $sumsFile | Where-Object { $_ -match [regex]::Escape($AssetName) } | Select-Object -First 1
      if ($line) {
        $expected = ($line -split '\s+')[0].ToLowerInvariant()
        $actual = (Get-FileHash $assetFile -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($expected -eq $actual) { Write-Info "checksum OK" }
        else { Fail "SHA256 verification FAILED for $AssetName (aborting for safety). Use -NoChecksum to skip." }
      } else {
        Write-Warn "checksum entry for $AssetName not found; skipping verification"
      }
    } catch {
      Write-Warn "checksum file unavailable; skipping verification"
    }
  }

  # ---------------------------------------------------------------- extract
  Write-Info "installing to $InstallDir ..."
  if (Test-Path $InstallDir) { Remove-Item $InstallDir -Recurse -Force }
  New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
  Expand-Archive -Path $assetFile -DestinationPath $InstallDir -Force

  # ---------------------------------------------------------------- PATH
  Refresh-PathEntry

  # ---------------------------------------------------------------- cleanup old version
  $OldVersion = ""
  if (Test-Path $versionFile) { $OldVersion = ([IO.File]::ReadAllText($versionFile)).Trim() }
  if ($OldVersion -and ($OldVersion -ne $Version) -and (Test-Path (Join-Path $LibDir $OldVersion))) {
    Remove-Item (Join-Path $LibDir $OldVersion) -Recurse -Force
    Write-Info "removed previous version $OldVersion"
  }
  [IO.File]::WriteAllText($versionFile, "$Version`n")

  # ---------------------------------------------------------------- verify
  $exe = Join-Path $InstallDir "scrcpy.exe"
  if (Test-Path $exe) {
    & $exe --version
    Write-Info "scrcpy $Version installed successfully."
  } else {
    Fail "installation failed: $exe is missing"
  }

  # ---------------------------------------------------------------- optional shortcut
  if (-not [string]::IsNullOrWhiteSpace($ShortcutName)) {
    New-Shortcut
  }
} finally {
  if (Test-Path $TempDir) { Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue }
}
