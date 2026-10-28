# CyberLab — Pentester Lab Setup & Vulnerability Assessment

A self-contained, repeatable **penetration-testing lab**: an attacker (Kali Linux)
and intentionally vulnerable targets on an **isolated** virtual network. Includes
fast downloaders, hypervisor installers, and an automated attack + report generator
for the VULNHUB **Basic Pentesting 1** machine.

> ⚠️ **Legal / ethical:** use only on machines you own or are authorised to test,
> on an **isolated** network. These tools are for a sandboxed college/CTF lab.

---

## What's in here

| File | What it does |
|---|---|
| `lab_fetch.sh` | Ultra-fast parallel downloader (aria2c, 16 conns/file) + checksum verify for the OVA, Kali ISO, Kali VMware image |
| `get_windows_server.sh` | Fast fetch + verify of the Windows Server eval ISO (for the AD lab) |
| `install_vmware.sh` | Install VMware Workstation **or** VirtualBox on Ubuntu/Debian |
| `install_vmware.ps1` | Install VMware Workstation **or** VirtualBox on Windows (winget) |
| `basic1_pwn.sh` | Automated attack on Basic Pentesting 1 → root, and writes the full lab report |
| `Setup-ADLab.ps1` | Windows Active Directory lab setup |
| `Lab3_Pentester_Lab_Report.md` | Generic lab writeup (Aim/Theory/Procedure/…) |
| `BasicPentesting1_Walkthrough.md` | Manual step-by-step cheat sheet |
| `vuln-assessment/` | DVWA / Juice Shop vulnerability-assessment project (before/after evidence, hardening) |

---

## Quick start (fastest path)

### 1. Install a hypervisor

**Ubuntu / Debian** (VirtualBox = easiest, no login needed):
```bash
curl -sL https://raw.githubusercontent.com/CyberJarvis/CyberLab/main/install_vmware.sh | sudo bash -s -- virtualbox
```

**Windows** (admin PowerShell):
```powershell
irm https://raw.githubusercontent.com/CyberJarvis/CyberLab/main/install_vmware.ps1 | iex
```

### 2. Download the lab images (fast + verified)

```bash
sudo apt install -y aria2 && \
curl -sL https://raw.githubusercontent.com/CyberJarvis/CyberLab/main/lab_fetch.sh | bash
```
Downloads `basic_pentesting_1.ova`, the Kali installer ISO, and the Kali VMware `.7z`
— all in parallel, auto-resumed, each checksum-verified. ~18 GB total.

Pick specific files: `... | bash -s -- kali ova`  (options: `ova kali kali-vm server`).

### 3. Import the VMs (see below), set the network, snapshot, attack.

---

## VMware / VirtualBox setup

### Basic Pentesting 1 (the target)
The OVA is VirtualBox-flavoured — importing in **VirtualBox** is simplest:
- **VirtualBox:** `File > Import Appliance` → pick `basic_pentesting_1.ova` → Import.
- **VMware:** `File > Open` → `basic_pentesting_1.ova` → accept the conversion.

Specs baked in: Ubuntu 64-bit, 2 vCPU, 4096 MB, one Host-only NIC. No login needed —
you attack it. (Creds, if you ever need them: `root` isn't required for the practical.)

### Kali Linux (the attacker) — two options
- **Prebuilt VMware VM (fastest):** the download is a `.7z`. Extract then open the `.vmx`:
  ```bash
  7z x kali-linux-2026.3-vmware-amd64.7z        # sudo apt install p7zip-full
  # then in VMware: File > Open > kali-linux-2026.3-vmware-amd64.vmx
  ```
  Default Kali creds: **kali / kali**.
- **From ISO (VirtualBox or VMware):** `New` VM → Linux / Debian 64-bit → attach
  `kali-linux-2026.3-installer-amd64.iso` → install → `sudo apt update && sudo apt full-upgrade -y`.

### Snapshot everything
After both VMs boot and get IPs, snapshot each so you can roll back after each run.

---

## Network setup — the important part (NAT etc.)

You want the attacker and target to **see each other** but stay **isolated from the
real campus LAN and the internet** (except Kali's updates). Use **two adapters on Kali**.

### What each adapter type means

| Adapter | Internet? | VMs see each other? | On real LAN? | Use it for |
|---|---|---|---|---|
| **NAT** | ✅ yes (via host) | ❌ no (each VM isolated) | ❌ no | Kali's internet (updates/tools) |
| **Host-only** | ❌ no | ✅ yes (host + VMs) | ❌ no | the lab network (attacker ↔ target) |
| **Internal Network** (VBox) / **LAN Segment** (VMware) | ❌ no | ✅ yes (VMs only, not host) | ❌ no | most-isolated lab network |
| **Bridged** | ✅ yes | ✅ (whole LAN) | ⚠️ **yes** | ❌ avoid — exposes the target |

### Recommended layout

**Kali (attacker) — 2 adapters:**
- Adapter 1 = **NAT** → gives Kali internet for `apt`/tools.
- Adapter 2 = **Host-only** (or Internal/LAN Segment) → the lab network.

**Target (Basic Pentesting 1) — 1 adapter:**
- Adapter 1 = **Host-only** (or Internal/LAN Segment) — **the same one as Kali's Adapter 2.**

> The rule: Kali's lab adapter and the target's adapter must be on the **same**
> Host-only/Internal network, or they can't talk. Never put the target on Bridged.

### VirtualBox — how to set it
1. `File > Host Network Manager` (or *Tools > Network*) → **Create** a Host-only network
   (e.g. `vboxnet0`, 192.168.56.0/24). Enable its DHCP server.
2. Target VM → `Settings > Network > Adapter 1` → *Host-only Adapter* → `vboxnet0`.
3. Kali VM → Adapter 1 = *NAT*; Adapter 2 = *Host-only Adapter* → `vboxnet0`.
4. (Most isolated alternative: set both to *Internal Network*, same name e.g. `lab`.)

### VMware — how to set it
1. `Edit > Virtual Network Editor` → VMnet1 is Host-only (e.g. 192.168.159.0/24),
   or add a **LAN Segment** for full isolation.
2. Target VM → Network Adapter → *Host-only* (VMnet1) **or** your LAN Segment.
3. Kali VM → add two adapters: *NAT* (VMnet8) **and** *Host-only / same LAN Segment*.

### Find the IPs
On Kali:
```bash
ip a                        # see your lab-adapter IP (e.g. 192.168.56.10)
sudo ./basic1_pwn.sh --discover   # scans the lab subnet for the target
```

---

## Run the attack + generate the report

On Kali, with the target booted on the same lab network:

```bash
git clone https://github.com/CyberJarvis/CyberLab.git && cd CyberLab
chmod +x basic1_pwn.sh
sudo ./basic1_pwn.sh <TARGET_IP>
```
Or one-liner:
```bash
curl -sL https://raw.githubusercontent.com/CyberJarvis/CyberLab/main/basic1_pwn.sh | sudo bash -s -- <TARGET_IP>
```

It will:
1. auto-install `nmap` / `metasploit-framework` / `netdiscover` if missing,
2. **recon** — `nmap -T4 -A`,
3. **exploit** — ProFTPD 1.3.3c backdoor via Metasploit → **root shell**,
4. **post-exploit** — `id`, `uname -a`, `ls /root`, grab the flag,
5. write `Lab3_Report_Basic1.md` (Aim → Objective → Theory → Procedure → Output →
   Conclusion) with your **real** output pasted in.

Don't know the target IP? `sudo ./basic1_pwn.sh --discover`.

---

## Windows Server / AD lab (optional)

```bash
# 1. get the ISO URL from the MS Eval Center, then:
curl -sL https://raw.githubusercontent.com/CyberJarvis/CyberLab/main/get_windows_server.sh | sudo bash -s -- "<EVAL_CENTER_URL>"
```
Build the Server VM from that ISO, then run `Setup-ADLab.ps1` inside it (admin PowerShell).

---

## Troubleshooting

- **Attacker can't reach target:** both must be on the **same** Host-only/Internal
  network. Check with `ip a` + `ping <target>`. Target must not be on NAT or Bridged.
- **No internet on Kali:** make sure Adapter 1 is **NAT** and it's enabled.
- **VMware modules won't load (Ubuntu):** disable Secure Boot in BIOS, or sign the
  modules. VirtualBox from apt avoids this.
- **`7z` not found:** `sudo apt install p7zip-full`.
- **aria2 not found:** `sudo apt install aria2` (or the script falls back to curl).
- **Exploit fails:** confirm `nmap` shows `ProFTPD 1.3.3c` on port 21 and you used the
  right target IP; re-run after a clean snapshot.

---

## Checksums (verified)

| File | SHA256 |
|---|---|
| `basic_pentesting_1.ova` | `191b5f53b2c5b9ee7d0e5737533914ad14c9b4bce45cab6947050b115b592c93` (MD5/SHA1 match VulnHub) |
| `kali-linux-2026.3-installer-amd64.iso` | `db9cbed33edb45727d16911813c2434fcd1419585007884153be22a03b30ec2f` (matches official Kali) |
| `kali-linux-2026.3-vmware-amd64.7z` | `f7a008dfc78de660f8e98b8cbbf94c36688e5441bf53d6c32643f0573177a096` (official Kali) |
