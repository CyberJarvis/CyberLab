#!/usr/bin/env bash
#
# get_windows_server.sh — Ultra-fast fetch of the Windows Server Evaluation ISO.
#
# Microsoft gates the download behind a short form and the direct link ROTATES,
# so there is no single hardcoded URL. You grab the current link once, then this
# script downloads it fast (aria2c, 16 connections) and verifies it.
#
# HOW TO GET THE URL (30 seconds):
#   1. Open: https://www.microsoft.com/en-us/evalcenter/download-windows-server-2022
#      (or .../download-windows-server-2025 for Server 2025)
#   2. Choose "Download the ISO" -> language English (64-bit).
#   3. When the save dialog / download starts, copy the real link
#      (right-click the download in your browser -> "Copy download link").
#      It looks like:
#        https://software-static.download.prss.microsoft.com/.../SERVER_EVAL_x64FRE_en-us.iso
#
# USAGE:
#   ./get_windows_server.sh "<PASTE_URL>"
#   SERVER_URL="<PASTE_URL>" ./get_windows_server.sh
#   DEST=/mnt/big ./get_windows_server.sh "<URL>"      # where to save
#
# Verify a specific build you already know the hash of:
#   SERVER_SHA="<sha256>" ./get_windows_server.sh "<URL>"
#
set -u
DEST="${DEST:-$(pwd)/cyberlab-images}"
CONN="${CONN:-16}"
FILE="${FILE:-SERVER_EVAL_x64FRE_en-us.iso}"
URL="${1:-${SERVER_URL:-}}"
# sha256 of the copy verified from the original lab pendrive (Server 2022 build).
# A different MS build will differ -> treated as a warning, not a hard failure.
SERVER_SHA="${SERVER_SHA:-3e4fa6d8507b554856fc9ca6079cc402df11a8b79344871669f0251535255325}"

have(){ command -v "$1" >/dev/null 2>&1; }
die(){ echo "[-] $*" >&2; exit 1; }

if [ -z "$URL" ]; then
  cat >&2 <<'MSG'
[-] No download URL given.

    Get it from the Microsoft Evaluation Center, then re-run with the link:

      https://www.microsoft.com/en-us/evalcenter/download-windows-server-2022

    Pick "Download the ISO" -> English (64-bit), start the download, then copy
    the real link (browser -> right-click the download -> Copy download link).

    Then:
      ./get_windows_server.sh "https://software-static.download.prss.microsoft.com/.../SERVER_EVAL_x64FRE_en-us.iso"
MSG
  exit 1
fi

case "$URL" in
  http://*|https://*) ;;
  *) die "That doesn't look like a URL: $URL" ;;
esac

mkdir -p "$DEST"
echo "[*] URL : $URL"
echo "[*] Dest: $DEST/$FILE"
echo

# ----- auto-install aria2 (fast) if possible ----------------------------------
if ! have aria2c; then
  echo "[!] aria2c not found."
  if have apt-get && [ "$(id -u)" -eq 0 ]; then
    echo "[*] Installing aria2..."; apt-get update -y >/dev/null 2>&1; apt-get install -y aria2 >/dev/null 2>&1
  elif have apt-get; then
    echo "[i] For max speed:  sudo apt install aria2   (continuing with curl)"
  fi
fi

# ----- download (resumable) ----------------------------------------------------
if have aria2c; then
  echo "[*] Downloading with aria2c ($CONN connections)..."
  aria2c -c -x "$CONN" -s "$CONN" -k 1M --max-tries=5 --retry-wait=3 \
         --console-log-level=warn --summary-interval=10 \
         -d "$DEST" -o "$FILE" "$URL" \
    || echo "[!] aria2c reported an error — verifying what downloaded."
else
  echo "[*] Downloading with curl (resumable)..."
  curl -L -C - --retry 5 -o "$DEST/$FILE" "$URL" || echo "[!] curl error — verifying anyway."
fi

[ -f "$DEST/$FILE" ] || die "Download produced no file."

# ----- sanity + verify ---------------------------------------------------------
echo
echo "=============== VERIFY ==============="
if have file; then
  ftype=$(file -b "$DEST/$FILE")
  echo "[i] type: $ftype"
  case "$ftype" in
    *ISO\ 9660*) echo "[OK] looks like a valid ISO" ;;
    *HTML*|*ASCII*) echo "[XX] got HTML/text, not an ISO — the link likely expired. Grab a fresh URL." ;;
  esac
fi

SHACMD=""; have sha256sum && SHACMD="sha256sum"; have shasum && SHACMD="shasum -a 256"
if [ -n "$SHACMD" ]; then
  got=$($SHACMD "$DEST/$FILE" | awk '{print $1}')
  echo "[i] sha256: $got"
  if [ "$got" = "$SERVER_SHA" ]; then
    echo "[OK] matches the known lab build."
  else
    echo "[!] sha256 differs from the known lab build (3e4fa6d8...)."
    echo "    That's expected if Microsoft updated the ISO — the file is still valid"
    echo "    as long as 'type' above says ISO 9660. Microsoft publishes no fixed hash."
  fi
fi
echo "======================================"
echo "[+] Saved: $DEST/$FILE"
