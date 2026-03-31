#!/bin/bash
# Ubuntu 24.04 Setup Script
# Installs: kernel 6.17.x, user/sudo, Docker, VS Code, Python AI/ML deps
# Usage: sudo bash setup.sh <username>
# After this completes, run: sudo bash install_rocm.sh

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "[ERROR] Run with sudo: sudo bash setup.sh <username>"
  exit 1
fi

TARGET_USER="${1:-}"
if [[ -z "$TARGET_USER" ]]; then
  echo "[ERROR] No username provided. Usage: sudo bash setup.sh <username>"
  exit 1
fi

TARGET_KERNEL="6.17.0-19-generic"

echo ""
echo "========================================================"
echo "  Ubuntu 24.04 Setup -- User: $TARGET_USER"
echo "========================================================"
echo ""

# ── System update ─────────────────────────────────────────────
echo "[..] Updating system packages..."
apt update -y && apt upgrade -y
echo "[OK] System updated."

# ── Kernel ────────────────────────────────────────────────────
echo ""
echo "[..] Checking kernel..."

if [[ "$(uname -r)" == "6.17"* ]]; then
  echo "[OK] Kernel $(uname -r) is 6.17 series -- skipping install."
else
  if ! dpkg -l 2>/dev/null | grep -q "linux-image-${TARGET_KERNEL}"; then
    echo "[..] Installing kernel ${TARGET_KERNEL}..."
    apt install -y \
      linux-image-${TARGET_KERNEL} \
      linux-headers-${TARGET_KERNEL} \
      linux-modules-extra-${TARGET_KERNEL}
    echo "[OK] Kernel ${TARGET_KERNEL} installed."
  fi

  # Pin GRUB to boot the target kernel.
  sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=saved/' /etc/default/grub
  update-grub 2>/dev/null
  GRUB_CFG="/boot/grub/grub.cfg"
  SUBMENU=$(grep -oP "(?<=submenu ')[^']*" "$GRUB_CFG" 2>/dev/null | grep -i advanced | head -1 || true)
  ENTRY=$(grep -oP "(?<=menuentry ')[^']*" "$GRUB_CFG" 2>/dev/null | grep "${TARGET_KERNEL}" | grep -v recovery | head -1 || true)
  if [[ -n "$SUBMENU" && -n "$ENTRY" ]]; then
    grub-set-default "${SUBMENU}>${ENTRY}"
  elif [[ -n "$ENTRY" ]]; then
    grub-set-default "$ENTRY"
  fi
  echo "[OK] GRUB pinned to ${TARGET_KERNEL}."

  echo ""
  echo "[!!] Reboot required to activate kernel ${TARGET_KERNEL}."
  echo "     Re-run this script after rebooting."
  read -rp "Reboot now? (y/n): " R
  [[ "$R" =~ ^[Yy]$ ]] && reboot || exit 0
fi

# ── User & sudo ───────────────────────────────────────────────
echo ""
if ! id "$TARGET_USER" &>/dev/null; then
  echo "[..] Creating user $TARGET_USER..."
  adduser --gecos "" --disabled-password "$TARGET_USER"
fi
if ! groups "$TARGET_USER" | grep -qw sudo; then
  usermod -aG sudo "$TARGET_USER"
fi
echo "[OK] User $TARGET_USER configured with sudo."

# ── Docker ────────────────────────────────────────────────────
echo ""
if command -v docker &>/dev/null; then
  echo "[OK] Docker already installed -- skipping."
else
  echo "[..] Installing Docker..."
  snap list docker &>/dev/null 2>&1 && snap remove docker || true
  apt install -y ca-certificates curl gnupg
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  if [[ ! -f /etc/apt/sources.list.d/docker.list ]]; then
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
      | tee /etc/apt/sources.list.d/docker.list > /dev/null
  fi
  apt update -y
  apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  echo "[OK] Docker installed."
fi
systemctl enable --now docker
groups "$TARGET_USER" | grep -qw docker || usermod -aG docker "$TARGET_USER"
echo "[OK] Docker group set for $TARGET_USER."

# ── VS Code ───────────────────────────────────────────────────
echo ""
if dpkg -l code &>/dev/null 2>&1; then
  echo "[OK] VS Code already installed -- skipping."
else
  echo "[..] Installing VS Code..."
  apt install -y wget gpg apt-transport-https
  wget -qO- https://packages.microsoft.com/keys/microsoft.asc \
    | gpg --dearmor > /etc/apt/keyrings/microsoft.gpg
  chmod a+r /etc/apt/keyrings/microsoft.gpg
  if [[ ! -f /etc/apt/sources.list.d/vscode.list ]]; then
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/microsoft.gpg] \
https://packages.microsoft.com/repos/code stable main" \
      | tee /etc/apt/sources.list.d/vscode.list > /dev/null
  fi
  apt update -y
  apt install -y code
  echo "[OK] VS Code installed."
fi

# ── Python AI/ML deps ─────────────────────────────────────────
echo ""
echo "[..] Installing Python AI/ML dependencies..."
apt install -y \
  python3 python3-venv python3-pip \
  espeak ffmpeg libsndfile1 portaudio19-dev \
  libcairo2-dev libgirepository1.0-dev \
  gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
  libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
  gir1.2-gstreamer-1.0 gir1.2-gst-plugins-base-1.0
echo "[OK] Python AI/ML dependencies installed."

# Set env var for MuJoCo GUI on Wayland (needs to happen after user exists).
TARGET_BASHRC="/home/${TARGET_USER}/.bashrc"
grep -q "PYGLFW_LIBRARY_VARIANT" "$TARGET_BASHRC" 2>/dev/null || \
  echo 'export PYGLFW_LIBRARY_VARIANT=x11' >> "$TARGET_BASHRC"
echo "[OK] PYGLFW_LIBRARY_VARIANT=x11 set in $TARGET_BASHRC."

# ── Done ──────────────────────────────────────────────────────
echo ""
echo "========================================================"
echo "  Setup complete!"
echo "  Docker  : $(docker --version 2>/dev/null || echo NOT FOUND)"
echo "  VS Code : $(dpkg -l code 2>/dev/null | awk '/^ii/{print $3}' || echo NOT FOUND)"
echo "  Kernel  : $(uname -r)"
echo ""
echo "  Next: sudo bash install_rocm.sh"
echo "========================================================"
