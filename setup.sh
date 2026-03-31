#!/bin/bash

# ============================================================
# Ubuntu 24.04 Setup Script
# Installs: Mainline Kernel, Docker Engine, Sudo, VS Code, AMD ROCm
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

TARGET_KERNEL="6.18.20-061820-generic"
KERNEL_BASE_URL="https://kernel.ubuntu.com/mainline/v6.18.20/amd64"

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
# STEP 2 -- Mainline Kernel + GRUB Pin
# ============================================================
# Run kernel install BEFORE ROCm so DKMS only ever sees 6.18 headers
# when amdgpu is registered. Mainline kernels are unsigned -- Secure
# Boot must be disabled before running this script.
# The script must be run a second time after rebooting to complete
# the remaining steps (Docker, VS Code, ROCm, Python).
# ============================================================
section "STEP 2 -- Mainline Kernel ${TARGET_KERNEL}"

RUNNING_KERNEL=$(uname -r)

if [[ "$RUNNING_KERNEL" == "${TARGET_KERNEL}"* ]]; then
  log "Already running kernel ${TARGET_KERNEL}. Continuing with remaining steps."
else
  if ! dpkg -l 2>/dev/null | grep -q "linux-image-unsigned-${TARGET_KERNEL}"; then
    log "Installing mainline kernel ${TARGET_KERNEL}..."

    apt install -y wget curl

    log "Fetching package filenames from kernel.ubuntu.com..."
    INDEX=$(curl -fsSL "${KERNEL_BASE_URL}/")

    DEB_HEADERS_ALL=$(echo "$INDEX" | grep -oP 'linux-headers-[0-9._-]+_all\.deb'                          | head -1)
    DEB_HEADERS=$(echo "$INDEX"     | grep -oP "linux-headers-${TARGET_KERNEL}_[^\"' ]+_amd64\.deb"        | head -1)
    DEB_IMAGE=$(echo "$INDEX"       | grep -oP "linux-image-unsigned-${TARGET_KERNEL}_[^\"' ]+_amd64\.deb" | head -1)
    DEB_MODULES=$(echo "$INDEX"     | grep -oP "linux-modules-${TARGET_KERNEL}_[^\"' ]+_amd64\.deb"        | head -1)
    DEB_MODULES_EXTRA=$(echo "$INDEX" | grep -oP "linux-modules-extra-${TARGET_KERNEL}_[^\"' ]+_amd64\.deb" | head -1 || true)

    [[ -z "$DEB_HEADERS" ]] && error "Could not resolve linux-headers filename from ${KERNEL_BASE_URL}"
    [[ -z "$DEB_IMAGE"   ]] && error "Could not resolve linux-image filename from ${KERNEL_BASE_URL}"
    [[ -z "$DEB_MODULES" ]] && error "Could not resolve linux-modules filename from ${KERNEL_BASE_URL}"

    KERNEL_TMP=$(mktemp -d)
    log "Downloading kernel packages..."
    [[ -n "$DEB_HEADERS_ALL"   ]] && wget -q "${KERNEL_BASE_URL}/${DEB_HEADERS_ALL}"   -O "${KERNEL_TMP}/headers-all.deb"
    wget -q "${KERNEL_BASE_URL}/${DEB_HEADERS}"       -O "${KERNEL_TMP}/headers.deb"
    wget -q "${KERNEL_BASE_URL}/${DEB_IMAGE}"          -O "${KERNEL_TMP}/image.deb"
    wget -q "${KERNEL_BASE_URL}/${DEB_MODULES}"        -O "${KERNEL_TMP}/modules.deb"
    [[ -n "$DEB_MODULES_EXTRA" ]] && wget -q "${KERNEL_BASE_URL}/${DEB_MODULES_EXTRA}" -O "${KERNEL_TMP}/modules-extra.deb"

    log "Installing kernel packages..."
    [[ -n "$DEB_HEADERS_ALL"   ]] && dpkg -i "${KERNEL_TMP}/headers-all.deb"
    dpkg -i "${KERNEL_TMP}/headers.deb"
    dpkg -i "${KERNEL_TMP}/modules.deb"
    dpkg -i "${KERNEL_TMP}/image.deb"
    [[ -n "$DEB_MODULES_EXTRA" ]] && dpkg -i "${KERNEL_TMP}/modules-extra.deb" || true
    apt install -f -y

    rm -rf "${KERNEL_TMP}"
    log "Kernel ${TARGET_KERNEL} installed."
  else
    log "Kernel ${TARGET_KERNEL} packages already present."
  fi

  log "Pinning GRUB to ${TARGET_KERNEL}..."
  GRUB_DEFAULT_VALUE="Advanced options for Ubuntu>Ubuntu, with Linux ${TARGET_KERNEL}"
  sed -i "s|^GRUB_DEFAULT=.*|GRUB_DEFAULT=\"${GRUB_DEFAULT_VALUE}\"|" /etc/default/grub
  sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=5/' /etc/default/grub
  update-grub
  log "GRUB pinned to: ${GRUB_DEFAULT_VALUE}"

  if grep -q "${TARGET_KERNEL}" /boot/grub/grub.cfg 2>/dev/null; then
    log "Verified: ${TARGET_KERNEL} found in grub.cfg"
  else
    warn "${TARGET_KERNEL} NOT found in grub.cfg -- verify kernel packages installed correctly."
  fi

  echo ""
  warn "Reboot required to activate kernel ${TARGET_KERNEL}."
  warn "Re-run this script after reboot to complete: Docker, VS Code, ROCm, Python."
  echo ""
  read -rp "  Reboot now? (y/n): " DO_REBOOT
  if [[ "$DO_REBOOT" =~ ^[Yy]$ ]]; then
    reboot
  else
    warn "Reboot skipped. Re-run this script after rebooting."
  fi
  exit 0
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

ROCM_DEB_URL="https://repo.radeon.com/amdgpu-install/7.2.1/ubuntu/noble/amdgpu-install_7.2.1.70201-1_all.deb"
ROCM_DEB="/tmp/amdgpu-install.deb"

if command -v amdgpu-install &>/dev/null; then
  warn "amdgpu-install already present ($(amdgpu-install --version 2>/dev/null || echo 'version unknown')). Skipping."
  warn "To change version: apt remove amdgpu-install"
else
  apt install -y python3-setuptools python3-wheel wget

  log "Validating ROCm installer URL..."
  if ! wget --spider -q "$ROCM_DEB_URL" 2>/dev/null; then
    error "ROCm URL not reachable: $ROCM_DEB_URL"
  fi

  wget -q "$ROCM_DEB_URL" -O "$ROCM_DEB"
  apt install -y "$ROCM_DEB"
  apt update -y

  # amdgpu-install may exit non-zero if amdgpu-dkms fails to build against
  # the mainline kernel (ROCm 7.2.1 DKMS does not support 6.18). The in-tree
  # amdgpu driver in kernel 6.18 is used instead -- ROCm userspace still installs.
  amdgpu-install -y --usecase=graphics,rocm || {
    warn "amdgpu-install failed -- amdgpu-dkms does not support kernel ${TARGET_KERNEL}."
    warn "Force-removing broken amdgpu-dkms. In-tree amdgpu driver will be used."
    dpkg --purge --force-all amdgpu-dkms 2>/dev/null || \
      dpkg --remove --force-remove-reinstreq amdgpu-dkms 2>/dev/null || true
    dpkg --configure -a 2>/dev/null || true
    log "ROCm userspace installed. amdgpu-dkms removed (unsupported on ${TARGET_KERNEL})."
  }

  rm -f "$ROCM_DEB"
  log "ROCm installed."
fi

for GRP in render video; do
  if getent group "$GRP" &>/dev/null; then
    if groups "$TARGET_USER" | grep -qw "$GRP"; then
      warn "'$TARGET_USER' already in $GRP group. Skipping."
    else
      usermod -aG "$GRP" "$TARGET_USER"
      log "Added '$TARGET_USER' to $GRP group."
    fi
  else
    warn "Group '$GRP' not found -- driver may not be fully installed."
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
