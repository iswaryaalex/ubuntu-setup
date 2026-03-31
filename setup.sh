#!/bin/bash

# ============================================================
# Ubuntu 24.04 Setup Script
# Installs: OEM Kernel, Docker Engine, Sudo, VS Code, AMD ROCm
# Usage: sudo bash setup.sh <username>
# ============================================================

if [ -z "${BASH_VERSION:-}" ]; then
  echo "[X] This script requires bash, not sh."
  echo "    Usage: sudo bash setup.sh <username>"
  exit 1
fi

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

log()     { echo -e "${GREEN}[OK] $1${NC}"; }
warn()    { echo -e "${YELLOW}[!!] $1${NC}"; }
error()   { echo -e "${RED}[XX] $1${NC}"; exit 1; }
section() { echo -e "\n${CYAN}--- $1 ---${NC}\n"; }

if [[ $EUID -ne 0 ]]; then
  error "This script must be run as root or with sudo."
fi

TARGET_USER="${1:-}"
if [[ -z "$TARGET_USER" ]]; then
  error "No username provided. Usage: sudo bash setup.sh <username>"
fi

TARGET_KERNEL="6.17.0-19-generic"

echo ""
echo "============================================================"
echo "  Ubuntu 24.04 Setup -- User: $TARGET_USER"
echo "  Kernel: $TARGET_KERNEL | Docker | VS Code | AMD ROCm | Python AI/ML"
echo "============================================================"
echo ""

# ============================================================
# STEP 1 -- System Update
# ============================================================
section "STEP 1 -- System Update"
apt update -y && apt upgrade -y
log "System updated."

# ============================================================
# STEP 2 -- OEM Kernel
# ============================================================
# Ubuntu OEM kernels are signed (Secure Boot safe) and available
# via apt. The 6.17.0-1012-oem kernel includes the Strix Halo
# KFD patches required for stable ROCm GPU compute on this platform.
# ============================================================
section "STEP 2 -- OEM Kernel ${TARGET_KERNEL}"

RUNNING_KERNEL=$(uname -r)

if [[ "$RUNNING_KERNEL" == "${TARGET_KERNEL}"* ]]; then
  log "Kernel ${TARGET_KERNEL} is already running. Skipping."
else
  if dpkg -l 2>/dev/null | grep -q "linux-image-${TARGET_KERNEL}"; then
    warn "Kernel ${TARGET_KERNEL} is installed but not yet active (running: ${RUNNING_KERNEL})."
    warn "Reboot to activate it before continuing with ROCm."
  else
    warn "Currently running: ${RUNNING_KERNEL}"
    log "Installing OEM kernel ${TARGET_KERNEL}..."
    apt install -y \
      linux-image-${TARGET_KERNEL} \
      linux-headers-${TARGET_KERNEL} \
      linux-modules-extra-${TARGET_KERNEL}
    log "Kernel ${TARGET_KERNEL} installed."
  fi

  log "Pinning GRUB to boot kernel ${TARGET_KERNEL}..."
  sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=saved/' /etc/default/grub
  update-grub 2>/dev/null

  GRUB_CFG="/boot/grub/grub.cfg"
  SUBMENU_ENTRY=$(grep -oP "(?<=submenu ')[^']*" "$GRUB_CFG" 2>/dev/null | grep -i "advanced" | head -1 || true)
  KERNEL_ENTRY=$(grep -oP "(?<=menuentry ')[^']*" "$GRUB_CFG" 2>/dev/null | grep "${TARGET_KERNEL}" | grep -v recovery | head -1 || true)

  if [[ -n "$SUBMENU_ENTRY" && -n "$KERNEL_ENTRY" ]]; then
    grub-set-default "${SUBMENU_ENTRY}>${KERNEL_ENTRY}"
    log "GRUB pinned to: ${SUBMENU_ENTRY} > ${KERNEL_ENTRY}"
  elif [[ -n "$KERNEL_ENTRY" ]]; then
    grub-set-default "$KERNEL_ENTRY"
    log "GRUB pinned to: ${KERNEL_ENTRY}"
  else
    warn "Could not auto-detect GRUB entry for ${TARGET_KERNEL} -- verify after reboot with: uname -r"
  fi

  echo ""
  warn "Kernel ${TARGET_KERNEL} requires a reboot before ROCm can be installed."
  warn "ROCm DKMS must build against the active kernel headers."
  read -rp "  Reboot now and re-run this script after? (y/n): " DO_REBOOT
  if [[ "$DO_REBOOT" =~ ^[Yy]$ ]]; then
    log "Rebooting..."
    reboot
  else
    error "Cannot continue safely without rebooting. Re-run after reboot."
  fi
fi

# ============================================================
# STEP 3 -- User Creation & Sudo Access
# ============================================================
section "STEP 3 -- User Creation & Sudo Access"

if id "$TARGET_USER" &>/dev/null; then
  warn "User '$TARGET_USER' already exists. Skipping creation."
else
  log "Creating user '$TARGET_USER'..."
  adduser --gecos "" --disabled-password "$TARGET_USER"
fi

if groups "$TARGET_USER" | grep -qw sudo; then
  warn "'$TARGET_USER' already in sudo group. Skipping."
else
  usermod -aG sudo "$TARGET_USER"
  log "Sudo access granted to '$TARGET_USER'."
fi

# ============================================================
# STEP 4 -- Docker Engine
# ============================================================
section "STEP 4 -- Docker Engine"

if command -v docker &>/dev/null; then
  warn "Docker already installed ($(docker --version)). Skipping."
  warn "If installed via snap, remove first: snap remove docker"
else
  if snap list docker &>/dev/null 2>&1; then
    warn "Removing conflicting Docker snap..."
    snap remove docker
    log "Docker snap removed."
  fi

  apt install -y ca-certificates curl gnupg lsb-release
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc

  if [[ ! -f /etc/apt/sources.list.d/docker.list ]]; then
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null
  else
    warn "Docker apt repo already present. Skipping."
  fi

  apt update -y
  apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  log "Docker installed."
fi

systemctl enable docker
systemctl start docker

if groups "$TARGET_USER" | grep -qw docker; then
  warn "'$TARGET_USER' already in docker group. Skipping."
else
  usermod -aG docker "$TARGET_USER"
  log "Added '$TARGET_USER' to docker group."
fi

# ============================================================
# STEP 5 -- Visual Studio Code
# ============================================================
section "STEP 5 -- Visual Studio Code"

if dpkg -l code &>/dev/null 2>&1; then
  warn "VS Code already installed. Skipping."
else
  apt install -y wget gpg apt-transport-https

  wget -qO- https://packages.microsoft.com/keys/microsoft.asc | \
    gpg --dearmor > /etc/apt/keyrings/microsoft.gpg
  chmod a+r /etc/apt/keyrings/microsoft.gpg

  if [[ ! -f /etc/apt/sources.list.d/vscode.list ]]; then
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/microsoft.gpg] \
https://packages.microsoft.com/repos/code stable main" | \
      tee /etc/apt/sources.list.d/vscode.list > /dev/null
  else
    warn "VS Code apt repo already present. Skipping."
  fi

  apt update -y
  apt install -y code
  log "VS Code installed."
fi

# ============================================================
# STEP 6 -- AMD ROCm
# ============================================================
section "STEP 6 -- AMD ROCm"

ACTIVE_KERNEL=$(uname -r)
if [[ "$ACTIVE_KERNEL" != "${TARGET_KERNEL}"* ]]; then
  error "Running kernel is ${ACTIVE_KERNEL}, expected ${TARGET_KERNEL}. Reboot into the correct kernel and re-run."
fi
log "Confirmed kernel ${ACTIVE_KERNEL} -- safe to install ROCm."

ROCM_DEB_URL="https://repo.radeon.com/amdgpu-install/7.2.1/ubuntu/noble/amdgpu-install_7.2.1.70201-1_all.deb"
ROCM_DEB="/tmp/amdgpu-install.deb"

if command -v amdgpu-install &>/dev/null; then
  warn "amdgpu-install already present ($(amdgpu-install --version 2>/dev/null || echo 'version unknown')). Skipping."
  warn "To change version: apt remove amdgpu-install"
else
  apt install -y python3-setuptools python3-wheel wget

  # Refresh package lists before downloading so dependency resolution uses
  # current metadata (matches the AMD manual install sequence).
  apt update -y

  log "Validating ROCm installer URL..."
  if ! wget --spider -q "$ROCM_DEB_URL" 2>/dev/null; then
    error "ROCm URL not reachable: $ROCM_DEB_URL"
  fi

  wget "$ROCM_DEB_URL" -O "$ROCM_DEB"
  # Install the amdgpu-install package (adds AMD apt repos to the system).
  apt install -y "$ROCM_DEB"
  rm -f "$ROCM_DEB"
  # Refresh again to pick up the newly added AMD repos before running the installer.
  apt update -y
  amdgpu-install -y --usecase=graphics,rocm
  log "ROCm installed."

  # The amdgpu kernel module must be loaded before render/video group
  # membership grants GPU access. This matches the AMD manual process which
  # reboots here, then adds groups in a separate step after the reboot.
  echo ""
  warn "ROCm requires a reboot to load the amdgpu kernel module before GPU"
  warn "group permissions can be applied. Re-run this script after rebooting."
  read -rp "  Reboot now and re-run this script after? (y/n): " DO_REBOOT
  if [[ "$DO_REBOOT" =~ ^[Yy]$ ]]; then
    log "Rebooting..."
    reboot
  else
    error "Cannot safely apply GPU group permissions without rebooting first. Re-run after reboot."
  fi
fi

# amdgpu-install creates the render and video groups; error out if they are
# missing rather than silently skipping -- a missing group means the driver
# install failed and GPU access will not work.
for GRP in render video; do
  if ! getent group "$GRP" &>/dev/null; then
    error "Group '$GRP' not found after ROCm install -- amdgpu-install may have failed. Check output above."
  fi
  if groups "$TARGET_USER" | grep -qw "$GRP"; then
    warn "'$TARGET_USER' already in $GRP group. Skipping."
  else
    usermod -aG "$GRP" "$TARGET_USER"
    log "Added '$TARGET_USER' to $GRP group."
  fi
done

# ============================================================
# STEP 7 -- Python AI/ML Dependencies
# ============================================================
section "STEP 7 -- Python AI/ML Dependencies"

apt install -y \
  python3 python3-venv python3-pip \
  espeak ffmpeg libsndfile1 portaudio19-dev \
  libcairo2-dev libgirepository1.0-dev \
  gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
  libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
  gir1.2-gstreamer-1.0 gir1.2-gst-plugins-base-1.0
log "Python AI/ML dependencies installed."

TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
TARGET_BASHRC="${TARGET_HOME}/.bashrc"
if grep -q "PYGLFW_LIBRARY_VARIANT" "$TARGET_BASHRC" 2>/dev/null; then
  warn "PYGLFW_LIBRARY_VARIANT already set in ${TARGET_BASHRC}. Skipping."
else
  echo 'export PYGLFW_LIBRARY_VARIANT=x11' >> "$TARGET_BASHRC"
  log "Added PYGLFW_LIBRARY_VARIANT=x11 to ${TARGET_BASHRC} (fixes MuJoCo GUI on Wayland)."
fi

if grep -q "HSA_OVERRIDE_GFX_VERSION" "$TARGET_BASHRC" 2>/dev/null; then
  warn "HSA_OVERRIDE_GFX_VERSION already set in ${TARGET_BASHRC}. Skipping."
else
  echo 'export HSA_OVERRIDE_GFX_VERSION=11.5.1' >> "$TARGET_BASHRC"
  log "Added HSA_OVERRIDE_GFX_VERSION=11.5.1 to ${TARGET_BASHRC} (required for ROCm/PyTorch on this GPU)."
fi

# ============================================================
# STEP 8 -- Verification Summary
# ============================================================
section "STEP 8 -- Verification Summary"

echo "============================================================"
echo "  COMPONENT CHECKS"
echo "============================================================"
echo "  Kernel          : $(uname -r)"
uname -r | grep -q "^${TARGET_KERNEL}" \
  && echo "  Kernel Match    : OK" \
  || echo "  Kernel Match    : NO -- expected ${TARGET_KERNEL}"
echo "  Docker          : $(docker --version 2>/dev/null || echo 'NOT FOUND')"
echo "  Docker Service  : $(systemctl is-active docker)"
echo "  VS Code         : $(dpkg -l code 2>/dev/null | awk '/^ii/{print $3}' || echo 'NOT FOUND')"
echo "  Sudo Access     : $(groups "$TARGET_USER" | grep -o sudo || echo 'NOT IN SUDO GROUP')"
echo "  AMDGPU Driver   : $(dkms status 2>/dev/null | grep amdgpu || echo 'NOT FOUND')"
echo "  Render Group    : $(groups "$TARGET_USER" | grep -o render || echo 'NOT IN RENDER GROUP')"
echo "  Video Group     : $(groups "$TARGET_USER" | grep -o video  || echo 'NOT IN VIDEO GROUP')"

echo ""
echo "  ROCm GPU Check:"
if command -v rocminfo &>/dev/null; then
  rocminfo 2>/dev/null | grep -E "Name:|Marketing Name:" | head -6 | \
    while read -r line; do echo "    $line"; done
else
  echo "    rocminfo not found -- reboot may be required"
fi

echo ""
echo "  OpenCL Check:"
if command -v clinfo &>/dev/null; then
  clinfo 2>/dev/null | grep -E "Board name:|Device Type:" | head -4 | \
    while read -r line; do echo "    $line"; done
else
  echo "    clinfo not found -- reboot may be required"
fi

echo ""
echo "============================================================"
log "Setup complete!"
warn "REBOOT REQUIRED for driver and group changes to take effect."
echo ""
echo "  After reboot verify with:"
echo "    uname -r        # should show ${TARGET_KERNEL}"
echo "    rocminfo"
echo "    clinfo"
echo "    dkms status"
echo ""
read -rp "  Reboot now? (y/n): " REBOOT_NOW
if [[ "$REBOOT_NOW" =~ ^[Yy]$ ]]; then
  reboot
else
  warn "Reboot skipped. Remember to reboot before using Docker, ROCm, or GPU."
fi
