# shrink-wsl-disk.ps1 — reclaim space from the Docker Desktop WSL2 VHDX.
#
# Usage (admin PowerShell):
#   shrink-wsl-disk.ps1
#
# Steps performed:
#   1. wsl --update                      (ensures WSL is current)
#   2. docker system prune -a --volumes  (frees blocks inside the VHDX)
#   3. wsl --shutdown                    (releases the VHDX file lock)
#   4. Optimize-VHD ... -Mode Full       (compacts the sparse VHDX)
#
# Requires: Windows 10/11 with WSL2, Docker Desktop, and the Hyper-V module
# (Optimize-VHD). Must be run from an elevated PowerShell session.

[CmdletBinding()]
param(
    [string]$VhdxPath = "$env:LOCALAPPDATA\Docker\wsl\disk\docker_data.vhdx"
)

$ErrorActionPreference = 'Stop'

function Test-Admin {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object System.Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-Command($cmd) {
    return [bool](Get-Command $cmd -ErrorAction SilentlyContinue)
}

if (-not (Test-Admin)) {
    Write-Error "This script must be run from an elevated PowerShell session."
    exit 1
}

if (-not (Test-Command wsl)) {
    Write-Error "wsl not found on PATH."
    exit 1
}

if (-not (Test-Command Optimize-VHD)) {
    Write-Error "Optimize-VHD not found. Enable the Hyper-V module: 'Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-Management-PowerShell'."
    exit 1
}

# ---- 1. Ensure WSL is up to date -------------------------------------------

Write-Host "→ wsl --update" -ForegroundColor Cyan
wsl --update

# ---- 2. Prune Docker resources (Docker Desktop must be running) -------------

if (Test-Command docker) {
    Write-Host "→ docker system prune -a --volumes" -ForegroundColor Cyan
    try {
        docker system prune -a --volumes -f
    } catch {
        Write-Warning "docker prune failed: $($_.Exception.Message)"
        Write-Warning "Make sure Docker Desktop is running, then re-run this script."
        exit 1
    }
} else {
    Write-Warning "docker not found on PATH — skipping prune step."
}

# ---- 3. Shut down WSL to release the VHDX lock ------------------------------

Write-Host "→ wsl --shutdown" -ForegroundColor Cyan
wsl --shutdown

# Give the host a moment to release file handles before Optimize-VHD.
Start-Sleep -Seconds 3

# ---- 4. Compact the VHDX ----------------------------------------------------

if (-not (Test-Path -LiteralPath $VhdxPath)) {
    Write-Error "VHDX not found at: $VhdxPath"
    Write-Error "Pass -VhdxPath to point at the correct file (older Docker Desktop versions used 'wsl\data\ext4.vhdx')."
    exit 1
}

$before = (Get-Item -LiteralPath $VhdxPath).Length

Write-Host "→ Optimize-VHD -Path '$VhdxPath' -Mode Full" -ForegroundColor Cyan
Optimize-VHD -Path $VhdxPath -Mode Full

$after  = (Get-Item -LiteralPath $VhdxPath).Length
$savedMB = [math]::Round(($before - $after) / 1MB, 1)
$afterMB = [math]::Round($after / 1MB, 1)

Write-Host ("✓ VHDX compacted: {0} MB now on disk (reclaimed {1} MB)." -f $afterMB, $savedMB) -ForegroundColor Green
