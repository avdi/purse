# shrink-wsl-disk.ps1 — reclaim space from the Docker Desktop WSL2 VHDX.
#
# Usage (admin PowerShell):
#   shrink-wsl-disk.ps1
#
# Steps performed:
#   1. wsl --update                      (ensures WSL is current)
#   2. docker system prune -a --volumes  (frees blocks inside the VHDX)
#   3. Stop Docker Desktop               (releases file handles on the VHDX;
#                                         graceful shutdown with force-kill
#                                         fallback after 30 s timeout)
#   4. wsl --shutdown                    (shuts down any remaining WSL distros
#                                         and releases the VHDX file lock)
#   5. Optimize-VHD ... -Mode Full       (compacts the sparse VHDX)
#
# Why step 3 is necessary:
#   Docker Desktop keeps its own WSL2 distros (docker-desktop,
#   docker-desktop-data) running as persistent background processes, each
#   holding an open handle on the VHDX file. If Docker Desktop is still alive
#   when Optimize-VHD runs, it will restart those distros and re-acquire the
#   lock, causing Optimize-VHD to fail with "The process cannot access the
#   file because it is being used by another process."
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

# ---- 3. Terminate Docker Desktop so it releases the VHDX file lock ----------
#
# Docker Desktop keeps the docker-desktop and docker-desktop-data WSL distros
# running even after a prune. Killing the main "Docker Desktop" process causes
# those distros to wind down; wsl --shutdown (step 4) then ensures they are
# fully gone before Optimize-VHD tries to open the file.

$ddName = 'Docker Desktop'
$ddProc = Get-Process -Name $ddName -ErrorAction SilentlyContinue
if ($ddProc) {
    Write-Host "→ Stopping $ddName (graceful)…" -ForegroundColor Cyan
    $ddProc | Stop-Process

    # Wait up to 30 s for a clean exit before escalating to force-kill.
    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-Process -Name $ddName -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 1
    }

    if (Get-Process -Name $ddName -ErrorAction SilentlyContinue) {
        Write-Warning "$ddName did not exit within 30 s — force-killing."
        Get-Process -Name $ddName -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep -Seconds 2
    } else {
        Write-Host "✓ $ddName exited cleanly." -ForegroundColor Green
    }
} else {
    Write-Warning "$ddName process not found — it may already be stopped."
}

# ---- 4. Shut down WSL to release the VHDX lock ------------------------------

Write-Host "→ wsl --shutdown" -ForegroundColor Cyan
wsl --shutdown

# Give the host a moment to release file handles before Optimize-VHD.
Start-Sleep -Seconds 3

# ---- 5. Compact the VHDX ----------------------------------------------------

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
