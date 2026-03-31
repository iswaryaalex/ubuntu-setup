#!/bin/bash
# ROCm 7.2.1 installer for Ubuntu 24.04 (noble) on kernel 6.17.x
# Usage: sudo bash install_rocm.sh
# Run once -> reboots -> run again to finish group setup.

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo: sudo bash install_rocm.sh"
  exit 1
fi

USER="${SUDO_USER:-$USER}"
BASHRC="/home/${USER}/.bashrc"

# ── Kernel check ──────────────────────────────────────────────
if [[ "$(uname -r)" != "6.17"* ]]; then
  echo "[ERROR] Wrong kernel: $(uname -r). Boot into a 6.17.x kernel first."
  exit 1
fi
echo "[OK] Kernel: $(uname -r)"

# ── Install ROCm (skipped on re-run) ──────────────────────────
if ! command -v amdgpu-install &>/dev/null; then
  apt install -y python3-setuptools python3-wheel wget
  apt update -y
  wget https://repo.radeon.com/amdgpu-install/7.2.1/ubuntu/noble/amdgpu-install_7.2.1.70201-1_all.deb \
       -O /tmp/amdgpu-install.deb
  apt install -y /tmp/amdgpu-install.deb
  rm -f /tmp/amdgpu-install.deb
  apt update -y
  amdgpu-install -y --usecase=graphics,rocm
  echo ""
  echo "[OK] ROCm installed. Reboot now, then re-run this script to set group permissions."
  read -rp "Reboot now? (y/n): " R
  [[ "$R" =~ ^[Yy]$ ]] && reboot || exit 0
fi

echo "[OK] ROCm already installed."

# ── Group permissions ──────────────────────────────────────────
usermod -aG render,video "$USER"
echo "[OK] Added $USER to render and video groups."

# ── Environment variables ──────────────────────────────────────
grep -q "HSA_OVERRIDE_GFX_VERSION" "$BASHRC" 2>/dev/null || \
  echo 'export HSA_OVERRIDE_GFX_VERSION=11.5.1' >> "$BASHRC"
echo "[OK] HSA_OVERRIDE_GFX_VERSION=11.5.1 set in $BASHRC"

# ── Done ───────────────────────────────────────────────────────
echo ""
echo "Setup complete. Reboot to activate GPU group access."
read -rp "Reboot now? (y/n): " R
[[ "$R" =~ ^[Yy]$ ]] && reboot || echo "Remember to reboot before using the GPU."
