<#
  install_vmware.ps1 — Install a hypervisor on Windows for the CyberLab.

  VMware Workstation Pro is free for personal use. This script installs it via
  winget (no manual download), with VirtualBox as the easy alternative.

  Run in an ADMIN PowerShell:
    Set-ExecutionPolicy Bypass -Scope Process -Force
    .\install_vmware.ps1              # installs VMware Workstation Pro
    .\install_vmware.ps1 virtualbox   # installs VirtualBox instead
    .\install_vmware.ps1 both         # installs both

  One-liner (admin PowerShell):
    irm https://raw.githubusercontent.com/CyberJarvis/CyberLab/main/install_vmware.ps1 | iex
#>

param([string]$Target = "vmware")

function Assert-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p  = New-Object Security.Principal.WindowsPrincipal($id)
  if (-not $p.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Write-Error "Run this in an ADMINISTRATOR PowerShell."; exit 1
  }
}

function Need-Winget {
  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Error "winget not found. Install 'App Installer' from the Microsoft Store, then re-run."
    exit 1
  }
}

function Install-Pkg($id, $name) {
  Write-Host "[*] Installing $name ($id)..."
  winget install --id $id -e --accept-source-agreements --accept-package-agreements
  if ($LASTEXITCODE -ne 0) { Write-Warning "$name install returned $LASTEXITCODE (may already be installed)." }
  else { Write-Host "[+] $name installed." }
}

Assert-Admin
Need-Winget

switch ($Target.ToLower()) {
  "vmware"     { Install-Pkg "VMware.WorkstationPro" "VMware Workstation Pro" }
  "virtualbox" { Install-Pkg "Oracle.VirtualBox"    "VirtualBox" }
  "vbox"       { Install-Pkg "Oracle.VirtualBox"    "VirtualBox" }
  "both"       {
    Install-Pkg "VMware.WorkstationPro" "VMware Workstation Pro"
    Install-Pkg "Oracle.VirtualBox"     "VirtualBox"
  }
  default { Write-Error "Unknown target '$Target'. Use: vmware | virtualbox | both"; exit 1 }
}

Write-Host ""
Write-Host "[i] 7-Zip (to extract the Kali .7z):"
winget install --id 7zip.7zip -e --accept-source-agreements --accept-package-agreements | Out-Null
Write-Host "[i] Done. Reboot if VMware asks. Then:"
Write-Host "    - VMware:     extract Kali .7z, open the .vmx ; File > Open for the .ova"
Write-Host "    - VirtualBox: File > Import Appliance for basic_pentesting_1.ova ; Kali from ISO"
