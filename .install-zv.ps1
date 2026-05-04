# chezmoi hooks.read-source-state.pre: install Zoho Vault CLI (zv) on Windows.
# Runs before chezmoi reads the source state on every apply, so it must exit
# fast when zv is already present. Mirrors .install-zv.sh for Linux.

if (Get-Command zv -ErrorAction SilentlyContinue) { exit 0 }

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

$installDir = Join-Path $HOME '.local\bin'
$exePath    = Join-Path $installDir 'zv.exe'

# Re-check by file existence in case ~/.local/bin isn't on PATH yet.
if (Test-Path -LiteralPath $exePath) { exit 0 }

Write-Host "Installing Zoho Vault CLI (zv)..."
New-Item -ItemType Directory -Force -Path $installDir | Out-Null

$tmpZip = Join-Path $env:TEMP 'zv_cli.zip'
try {
    Invoke-WebRequest `
        -Uri 'https://downloads.zohocdn.com/vault-cli-desktop/win/zv_cli.zip' `
        -OutFile $tmpZip `
        -UseBasicParsing
    Expand-Archive -LiteralPath $tmpZip -DestinationPath $installDir -Force
} finally {
    Remove-Item -LiteralPath $tmpZip -Force -ErrorAction SilentlyContinue
}

Write-Host "zv installed at $exePath"
