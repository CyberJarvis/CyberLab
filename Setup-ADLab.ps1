<#
.SYNOPSIS
  Fully automated AD Enumeration Lab builder. One run does everything:
  promotes VM to a Domain Controller, reboots, auto-resumes after reboot,
  creates sample users/groups with a deliberate privilege misconfiguration,
  and relaxes anonymous access for enumeration practice.

.USAGE (on the VM, elevated PowerShell)
  Local file:
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
    .\Setup-ADLab.ps1

  One-liner from GitHub raw URL (after you push it):
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
    iwr -useb https://raw.githubusercontent.com/<you>/<repo>/main/Setup-ADLab.ps1 -OutFile C:\Setup-ADLab.ps1
    C:\Setup-ADLab.ps1

  That's it. It installs AD DS, promotes to DC, reboots, logs back in as
  itself via a RunOnce entry, finishes creating users/groups/misconfig,
  relaxes anonymous access, and writes a done-marker + transcript log.

.NOTES
  Lab-only. Script must live at a stable local path (it copies itself to
  C:\ADLab\Setup-ADLab.ps1 on first run so the RunOnce resume can find it
  after reboot, even if you ran it from a USB stick / temp download path).
#>

[CmdletBinding()]
param(
    [string]$DomainName      = "lab.local",
    [string]$NetbiosName     = "LAB",
    [string]$DefaultPassword = "Passw0rd@123"
)

$ErrorActionPreference = "Stop"

$WorkDir      = "C:\ADLab"
$SelfPath     = Join-Path $WorkDir "Setup-ADLab.ps1"
$StateFile    = Join-Path $WorkDir "phase.state"
$LogFile      = Join-Path $WorkDir "setup.log"
$RunOnceKey   = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
$RunOnceName  = "ADLabResume"

function Assert-Elevated {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Run this script in an elevated (Administrator) PowerShell session."
    }
}

function Write-Log($msg) {
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
    Write-Host $line -ForegroundColor Cyan
    Add-Content -Path $LogFile -Value $line
}

function Get-Phase {
    if (Test-Path $StateFile) { return (Get-Content $StateFile -Raw).Trim() }
    return "A"
}

function Set-Phase($phase) {
    Set-Content -Path $StateFile -Value $phase
}

function Register-ResumeAfterReboot {
    # Re-run this same script, elevated, as the next user logon via RunOnce.
    $cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$SelfPath`""
    New-Item -Path $RunOnceKey -Force | Out-Null
    Set-ItemProperty -Path $RunOnceKey -Name $RunOnceName -Value $cmd
    Write-Log "Registered RunOnce resume: $cmd"
}

function Unregister-Resume {
    Remove-ItemProperty -Path $RunOnceKey -Name $RunOnceName -ErrorAction SilentlyContinue
}

function Invoke-PhaseA {
    Write-Log "[Phase A] Installing AD DS role and promoting to Domain Controller..."
    Install-WindowsFeature AD-Domain-Services -IncludeManagementTools | Out-Null

    $safeModePw = ConvertTo-SecureString $DefaultPassword -AsPlainText -Force

    Set-Phase "B"
    Register-ResumeAfterReboot

    Write-Log "Promoting now. Machine will reboot automatically and resume as Phase B."
    Install-ADDSForest `
        -DomainName $DomainName `
        -DomainNetbiosName $NetbiosName `
        -InstallDns `
        -SafeModeAdministratorPassword $safeModePw `
        -Force `
        -NoRebootOnCompletion:$false
    # Reboot happens here; script execution ends. RunOnce picks it back up
    # after the next interactive logon as LAB\Administrator.
}

function Invoke-PhaseB {
    Write-Log "[Phase B] Creating sample users, groups, and a deliberate misconfiguration..."
    Import-Module ActiveDirectory

    $pw = ConvertTo-SecureString $DefaultPassword -AsPlainText -Force

    foreach ($user in @("alice", "bob")) {
        if (-not (Get-ADUser -Filter "SamAccountName -eq '$user'" -ErrorAction SilentlyContinue)) {
            New-ADUser -Name $user -SamAccountName $user -AccountPassword $pw -Enabled $true
            Write-Log "  created user: $user"
        } else {
            Write-Log "  user already exists: $user"
        }
    }

    if (-not (Get-ADUser -Filter "SamAccountName -eq 'svc_sql'" -ErrorAction SilentlyContinue)) {
        New-ADUser -Name "svc_sql" -SamAccountName svc_sql -AccountPassword $pw `
            -Enabled $true -PasswordNeverExpires $true
        Write-Log "  created service account: svc_sql (PasswordNeverExpires = true)"
    }

    if (-not (Get-ADGroup -Filter "Name -eq 'IT-Admins'" -ErrorAction SilentlyContinue)) {
        New-ADGroup -Name "IT-Admins" -GroupScope Global
        Write-Log "  created group: IT-Admins"
    }

    Add-ADGroupMember -Identity "Domain Admins" -Members bob
    Add-ADGroupMember -Identity "IT-Admins" -Members alice
    Write-Log "[Phase B] Done. 'bob' is a member of Domain Admins (intentional finding)."

    Set-Phase "C"
    Invoke-PhaseC
}

function Invoke-PhaseC {
    Write-Log "[Phase C] Relaxing anonymous access (LAB ONLY, insecure)..."
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "RestrictAnonymous" -Value 0
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "EveryoneIncludesAnonymous" -Value 1
    Write-Log "[Phase C] Done."

    Set-Phase "Done"
    Unregister-Resume
    Write-Log "AD lab build complete. Domain: $DomainName  NetBIOS: $NetbiosName"
    Write-Log "Revert anonymous-access relaxation later with Restore-AnonymousRestrictions.ps1 (see below)."

    $restoreScript = Join-Path $WorkDir "Restore-AnonymousRestrictions.ps1"
    @'
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "RestrictAnonymous" -Value 1
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "EveryoneIncludesAnonymous" -Value 0
Write-Host "Reverted anonymous-access relaxation." -ForegroundColor Cyan
'@ | Set-Content -Path $restoreScript
}

# ---- main ----
Assert-Elevated
New-Item -Path $WorkDir -ItemType Directory -Force | Out-Null

# Copy self to the stable path so the post-reboot RunOnce entry can find it,
# regardless of where this script was originally launched from.
if ((Resolve-Path $PSCommandPath).Path -ne (Resolve-Path -Path $SelfPath -ErrorAction SilentlyContinue)) {
    Copy-Item -Path $PSCommandPath -Destination $SelfPath -Force
}

$phase = Get-Phase
Write-Log "Resuming at phase: $phase"

switch ($phase) {
    "A"    { Invoke-PhaseA }
    "B"    { Invoke-PhaseB }
    "C"    { Invoke-PhaseC }
    "Done" { Write-Log "Already complete. Delete $StateFile to rebuild." }
}
