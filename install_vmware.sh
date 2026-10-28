#!/usr/bin/env bash
#
# install_vmware.sh — Install a hypervisor on Ubuntu/Debian for the CyberLab.
#
# VMware Workstation Pro is now FREE for personal use, but Broadcom gates the
# download behind a login, so it can't be curl'd directly. This script:
#   * installs the build dependencies VMware needs,
#   * installs a VMware .bundle if you point it at one you downloaded,
#   * OR installs VirtualBox (one command, no login) as the easy alternative.
#
# Usage:
#   sudo ./install_vmware.sh virtualbox                 # easy path (recommended)
#   sudo ./install_vmware.sh vmware /path/to/VMware-Workstation-*.bundle
#   sudo ./install_vmware.sh deps                       # just the kernel build deps
#
set -u
die(){ echo "[-] $*" >&2; exit 1; }
have(){ command -v "$1" >/dev/null 2>&1; }
[ "$(id -u)" -eq 0 ] || die "Run with sudo:  sudo $0 $*"

MODE="${1:-virtualbox}"

install_deps(){
  echo "[*] Installing kernel headers + build tools..."
  apt-get update -y
  apt-get install -y build-essential "linux-headers-$(uname -r)" \
                     gcc make perl p7zip-full curl || die "dep install failed"
  echo "[+] Dependencies installed."
}

case "$MODE" in
  deps)
    install_deps
    ;;

  virtualbox|vbox)
    echo "[*] Installing VirtualBox from Ubuntu repos..."
    apt-get update -y
    apt-get install -y virtualbox virtualbox-ext-pack p7zip-full \
      || die "VirtualBox install failed. Try: apt install virtualbox"
    echo
    echo "[+] VirtualBox installed.  Launch:  virtualbox"
    echo "[i] Import the OVA:    File > Import Appliance > basic_pentesting_1.ova"
    echo "[i] Kali from ISO:     New > Linux/Debian 64 > attach kali-...-installer.iso"
    echo "[i] (The Kali .7z is a VMware image — for VirtualBox just use the ISO.)"
    ;;

  vmware)
    BUNDLE="${2:-}"
    [ -n "$BUNDLE" ] || die "Give the bundle path: sudo $0 vmware /path/to/VMware-Workstation-*.bundle
   Download it (free, personal) after login at:
   https://www.vmware.com/products/workstation-pro.html  (via Broadcom portal)"
    [ -f "$BUNDLE" ] || die "Not found: $BUNDLE"
    install_deps
    echo "[*] Installing VMware Workstation from $BUNDLE ..."
    chmod +x "$BUNDLE"
    "$BUNDLE" --console --required --eulas-agreed || die "VMware installer failed."
    echo "[*] Building VMware kernel modules..."
    vmware-modconfig --console --install-all 2>/dev/null || \
      echo "[!] Module build may need a reboot or Secure Boot disabled/signed."
    echo
    echo "[+] VMware Workstation installed.  Launch:  vmware"
    echo "[i] Open the Kali VM:  extract the .7z then open the .vmx."
    echo "[i] Import the OVA:    File > Open > basic_pentesting_1.ova"
    ;;

  *)
    die "Unknown mode '$MODE'. Use: virtualbox | vmware <bundle> | deps"
    ;;
esac

echo
echo "[i] Secure Boot note: if modules won't load, disable Secure Boot in BIOS,"
echo "    or sign the modules. VirtualBox from apt usually just works."
