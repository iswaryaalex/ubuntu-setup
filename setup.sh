#!/bin/bash
# Ubuntu 24.04 Setup Script
# Usage: sudo bash setup.sh <username>
# Re-run after each reboot -- safe to run multiple times.

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "[ERROR] Run with sudo: sudo bash setup.sh <username>"
  exit 1
fi

TARGET_USER="${1:-}"
if [[ -z "$TARGET_USER" ]]; then
  echo "[ERROR] Usage: sudo bash setup.sh <username>"
  exit 1
fi

TARGET_KERNEL="6.17.0-19-generic"
BASHRC="/home/${TARGET_USER}/.bashrc"

echo ""
echo "================================================"
echo "  Ubuntu 24.04 Setup  |  User: $TARGET_USER"
echo "================================================"

# ── 1. System update ──────────────────────────────
apt update -y && apt upgrade -y

# ── 2. Kernel ─────────────────────────────────────
if [[ "$(uname -r)" != "6.17"* ]]; then
  apt install -y \
    linux-image-${TARGET_KERNEL} \
    linux-headers-${TARGET_KERNEL} \
    linux-modules-extra-${TARGET_KERNEL}

  sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=saved/' /etc/default/grub
  update-grub 2>/dev/null

  GRUB_CFG="/boot/grub/grub.cfg"
  SUBMENU=$(grep -oP "(?<=submenu ')[^']*" "$GRUB_CFG" 2>/dev/null | grep -i advanced | head -1 || true)
  ENTRY=$(grep -oP "(?<=menuentry ')[^']*" "$GRUB_CFG" 2>/dev/null | grep "${TARGET_KERNEL}" | grep -v recovery | head -1 || true)
  [[ -n "$SUBMENU" && -n "$ENTRY" ]] && grub-set-default "${SUBMENU}>${ENTRY}" || grub-set-default "$ENTRY"

  echo "[OK] Kernel ${TARGET_KERNEL} installed. Reboot and re-run this script."
  read -rp "Reboot now? (y/n): " R && [[ "$R" =~ ^[Yy]$ ]] && reboot || exit 0
fi
echo "[OK] Kernel: $(uname -r)"

# ── 3. User & sudo ────────────────────────────────
id "$TARGET_USER" &>/dev/null || adduser --gecos "" --disabled-password "$TARGET_USER"
usermod -aG sudo "$TARGET_USER"
echo "[OK] User $TARGET_USER configured."

# ── 4. Docker ─────────────────────────────────────
apt install -y ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt update -y
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker
usermod -aG docker "$TARGET_USER"
echo "[OK] Docker installed."

# ── 5. VS Code ────────────────────────────────────
apt install -y wget gpg apt-transport-https
wget -qO- https://packages.microsoft.com/keys/microsoft.asc \
  | gpg --dearmor > /etc/apt/keyrings/microsoft.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/microsoft.gpg] \
https://packages.microsoft.com/repos/code stable main" \
  | tee /etc/apt/sources.list.d/vscode.list > /dev/null
apt update -y && apt install -y code
echo "[OK] VS Code installed."

# ── 6. Python AI/ML deps ──────────────────────────
apt install -y \
  python3 python3-venv python3-pip \
  espeak ffmpeg libsndfile1 portaudio19-dev \
  libcairo2-dev libgirepository1.0-dev \
  gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
  libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
  gir1.2-gstreamer-1.0 gir1.2-gst-plugins-base-1.0
echo "[OK] Python AI/ML deps installed."

# ── 7. ROCm ───────────────────────────────────────
if ! command -v amdgpu-install &>/dev/null; then
  apt install -y python3-setuptools python3-wheel
  apt update -y
  wget https://repo.radeon.com/amdgpu-install/7.2.1/ubuntu/noble/amdgpu-install_7.2.1.70201-1_all.deb \
       -O /tmp/amdgpu-install.deb
  apt install -y /tmp/amdgpu-install.deb
  rm -f /tmp/amdgpu-install.deb
  apt update -y
  amdgpu-install -y --usecase=graphics,rocm
  echo "[OK] ROCm installed. Reboot and re-run this script to finish group setup."
  read -rp "Reboot now? (y/n): " R && [[ "$R" =~ ^[Yy]$ ]] && reboot || exit 0
fi
echo "[OK] ROCm ready."

# ── 8. GPU groups & env vars ──────────────────────
usermod -aG render,video "$TARGET_USER"
echo "[OK] $TARGET_USER added to render and video groups."

grep -q "HSA_OVERRIDE_GFX_VERSION" "$BASHRC" 2>/dev/null || \
  echo 'export HSA_OVERRIDE_GFX_VERSION=11.5.1' >> "$BASHRC"

grep -q "PYGLFW_LIBRARY_VARIANT" "$BASHRC" 2>/dev/null || \
  echo 'export PYGLFW_LIBRARY_VARIANT=x11' >> "$BASHRC"
echo "[OK] Environment variables set in $BASHRC."

# ── Done ──────────────────────────────────────────
echo ""
echo "================================================"
echo "  All done! Reboot to activate all changes."
echo "  Verify after reboot: rocminfo | dkms status"
echo "================================================"
read -rp "Reboot now? (y/n): " R && [[ "$R" =~ ^[Yy]$ ]] && reboot || echo "[!!] Remember to reboot."
