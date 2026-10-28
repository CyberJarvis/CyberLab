#!/usr/bin/env bash
#
# lab_fetch.sh — Ultra-fast downloader for the CyberLab images.
#   * aria2c with 16 parallel connections per file (falls back to curl -C -)
#   * downloads up to 3 files at once
#   * auto-resumes partial downloads
#   * verifies each file against a known-good checksum
#
# Usage:
#   ./lab_fetch.sh                 # download everything (Server ISO skipped unless URL set)
#   ./lab_fetch.sh kali            # only Kali installer ISO
#   ./lab_fetch.sh ova kali        # pick any of: ova kali kali-vm server
#   SERVER_URL="https://.../SERVER_EVAL_x64FRE_en-us.iso" ./lab_fetch.sh server
#
# Put downloads somewhere with space:  DEST=/path ./lab_fetch.sh
#
set -u
DEST="${DEST:-$(pwd)/cyberlab-images}"
CONN="${CONN:-16}"               # parallel connections per file
JOBS="${JOBS:-3}"                # files downloaded simultaneously
mkdir -p "$DEST"

have(){ command -v "$1" >/dev/null 2>&1; }
die(){ echo "[-] $*" >&2; exit 1; }

# ----- the images: name | url | filename | sha256 -----------------------------
#  Kali URLs redirect to the nearest mirror automatically.
#  Windows Server eval has no public hash and a rotating URL -> set SERVER_URL yourself.
OVA_URL="https://download.vulnhub.com/basicpentesting/basic_pentesting_1.ova"
OVA_FILE="basic_pentesting_1.ova"
OVA_SHA="191b5f53b2c5b9ee7d0e5737533914ad14c9b4bce45cab6947050b115b592c93"

KALI_URL="https://cdimage.kali.org/kali-2026.3/kali-linux-2026.3-installer-amd64.iso"
KALI_FILE="kali-linux-2026.3-installer-amd64.iso"
KALI_SHA="db9cbed33edb45727d16911813c2434fcd1419585007884153be22a03b30ec2f"

KALIVM_URL="https://cdimage.kali.org/kali-2026.3/kali-linux-2026.3-vmware-amd64.7z"
KALIVM_FILE="kali-linux-2026.3-vmware-amd64.7z"
KALIVM_SHA="f7a008dfc78de660f8e98b8cbbf94c36688e5441bf53d6c32643f0573177a096"

SERVER_URL="${SERVER_URL:-}"     # get from MS Eval Center; filename below
SERVER_FILE="SERVER_EVAL_x64FRE_en-us.iso"
SERVER_SHA="3e4fa6d8507b554856fc9ca6079cc402df11a8b79344871669f0251535255325"  # from your drive copy (not an official MS hash)

# ----- which to fetch ----------------------------------------------------------
PICK="$*"
[ -z "$PICK" ] && PICK="ova kali kali-vm server"

# build parallel download list (url \t filename)
DLFILE="$DEST/.aria_list.txt"
: > "$DLFILE"
want(){ case " $PICK " in *" $1 "*) return 0;; *) return 1;; esac; }

add(){ # name url file
  local n="$1" u="$2" f="$3"
  [ -z "$u" ] && { echo "[!] skipping $n — no URL set (see SERVER_URL)"; return; }
  printf '%s\n  out=%s\n  dir=%s\n' "$u" "$f" "$DEST" >> "$DLFILE"
  echo "  queued: $f"
}

echo "[*] Destination: $DEST"
echo "[*] Selecting:  $PICK"
want ova     && add "Basic Pentesting 1 OVA" "$OVA_URL"    "$OVA_FILE"
want kali    && add "Kali installer ISO"      "$KALI_URL"   "$KALI_FILE"
want kali-vm && add "Kali VMware (.7z)"       "$KALIVM_URL" "$KALIVM_FILE"
want server  && add "Windows Server eval ISO" "$SERVER_URL" "$SERVER_FILE"

[ -s "$DLFILE" ] || die "Nothing queued. Pick: ova kali kali-vm server (and set SERVER_URL for server)."

# ----- download ----------------------------------------------------------------
echo
if have aria2c; then
  echo "[*] Downloading with aria2c ($CONN connections/file, $JOBS files at once)..."
  aria2c -c -x "$CONN" -s "$CONN" -k 1M -j "$JOBS" \
         --max-tries=5 --retry-wait=3 --console-log-level=warn \
         --summary-interval=10 -i "$DLFILE" \
    || echo "[!] aria2c reported an error — will verify what downloaded."
else
  echo "[!] aria2c not installed (install for max speed: 'sudo apt install aria2' / 'brew install aria2')."
  echo "[*] Falling back to parallel curl (resumable, single stream each)..."
  # fetch urls back out of the list and curl them in parallel with -C - (resume)
  grep -E '^https?://' "$DLFILE" | while read -r url; do
    f=$(awk -v u="$url" '$0==u{getline; sub(/^  out=/,""); print}' "$DLFILE")
    ( curl -L -C - --retry 5 -o "$DEST/$f" "$url" && echo "[+] done: $f" ) &
  done
  wait
fi
rm -f "$DLFILE"

# ----- verify ------------------------------------------------------------------
echo
echo "=============== VERIFY ==============="
SHACMD=""; have sha256sum && SHACMD="sha256sum"; have shasum && SHACMD="shasum -a 256"
[ -z "$SHACMD" ] && die "No sha256 tool found to verify."

check(){ # file expected_sha label
  local f="$DEST/$1" exp="$2" lbl="$3"
  [ -f "$f" ] || { echo "[ ] $lbl — not downloaded"; return; }
  local got; got=$($SHACMD "$f" | awk '{print $1}')
  if [ "$got" = "$exp" ]; then echo "[OK] $lbl — checksum verified"; \
  else echo "[XX] $lbl — CHECKSUM MISMATCH"; echo "       expected $exp"; echo "       got      $got"; fi
}
want ova     && check "$OVA_FILE"    "$OVA_SHA"    "Basic Pentesting 1 OVA"
want kali    && check "$KALI_FILE"   "$KALI_SHA"   "Kali installer ISO"
want kali-vm && check "$KALIVM_FILE" "$KALIVM_SHA" "Kali VMware (.7z)"
want server  && [ -n "$SERVER_URL" ] && check "$SERVER_FILE" "$SERVER_SHA" "Windows Server eval ISO"

echo "======================================"
echo "[+] Files in: $DEST"
echo "[i] Kali VMware is a .7z — extract it:  7z x $KALIVM_FILE   (sudo apt install p7zip-full)"
