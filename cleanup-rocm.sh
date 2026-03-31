#!/bin/bash

# ============================================================
# ROCm Cleanup Script
# Removes ROCm/amdgpu DKMS modules and packages that were
# built against the wrong kernel (e.g. 6.17), leaving the
# machine ready for a clean re-install via setup.sh on 6.18.
# Usage: sudo bash cleanup-rocm.sh
# ============================================================

if [ -z "${BASH_VERSION:-}" ]; then
  echo "[X] This script requires bash, not sh."
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

echo ""
echo "============================================================"
echo "  ROCm / amdgpu DKMS Cleanup"
echo "  Running kernel: $(uname -r)"
echo "============================================================"
echo ""
warn "This will remove all ROCm packages, amdgpu DKMS modules,"
warn "and amdgpu-install so setup.sh can reinstall them cleanly."
echo ""
read -rp "  Continue? (y/n): " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { warn "Aborted."; exit 0; }

# ============================================================
# STEP 1 -- Remove DKMS amdgpu modules
# ============================================================
section "STEP 1 -- Remove amdgpu DKMS modules"

DKMS_AMDGPU_VERSIONS=$(dkms status 2>/dev/null | grep -oP 'amdgpu/[^,]+' | sort -u || true)

if [[ -z "$DKMS_AMDGPU_VERSIONS" ]]; then
  warn "No amdgpu DKMS modules found. Skipping."
else
  while IFS= read -r entry; do
    VERSION="${entry#amdgpu/}"
    log "Removing DKMS module: amdgpu/${VERSION}"
    dkms remove "amdgpu/${VERSION}" --all 2>/dev/null || warn "dkms remove failed for amdgpu/${VERSION} -- may already be partially removed."
  done <<< "$DKMS_AMDGPU_VERSIONS"
  log "amdgpu DKMS modules removed."
fi

# ============================================================
# STEP 2 -- Remove ROCm and amdgpu packages
# ============================================================
section "STEP 2 -- Remove ROCm and amdgpu packages"

# Use amdgpu-install uninstall if available
if command -v amdgpu-install &>/dev/null; then
  log "Running amdgpu-install --uninstall..."
  amdgpu-install --uninstall -y 2>/dev/null || warn "amdgpu-install --uninstall returned non-zero -- continuing manual cleanup."
fi

# Remove all rocm/amdgpu packages
ROCM_PKGS=$(dpkg -l 2>/dev/null | awk '/^ii/ && /amdgpu|rocm|hip|opencl-rocm|hsa-rocr|comgr|rocblas|rocsolver|rocfft|rccl|migraphx|amd-smi/' '{print $2}' || true)

if [[ -z "$ROCM_PKGS" ]]; then
  warn "No ROCm/amdgpu packages found via dpkg. Skipping."
else
  log "Removing packages..."
  # shellcheck disable=SC2086
  apt remove --purge -y $ROCM_PKGS 2>/dev/null || warn "Some packages could not be removed -- continuing."
fi

# Remove amdgpu-install itself
if dpkg -l amdgpu-install &>/dev/null 2>&1; then
  apt remove --purge -y amdgpu-install
  log "amdgpu-install removed."
fi

apt autoremove -y
apt clean
log "ROCm packages removed."

# ============================================================
# STEP 3 -- Remove leftover DKMS build artifacts
# ============================================================
section "STEP 3 -- Remove leftover DKMS build artifacts"

if [[ -d /var/lib/dkms/amdgpu ]]; then
  rm -rf /var/lib/dkms/amdgpu
  log "Removed /var/lib/dkms/amdgpu"
else
  warn "/var/lib/dkms/amdgpu not found. Skipping."
fi

# ============================================================
# STEP 4 -- Remove ROCm apt repo
# ============================================================
section "STEP 4 -- Remove ROCm apt repo"

for f in /etc/apt/sources.list.d/amdgpu.list /etc/apt/sources.list.d/rocm.list; do
  if [[ -f "$f" ]]; then
    rm -f "$f"
    log "Removed $f"
  fi
done

apt update -y
log "Apt repo cleaned."

# ============================================================
# Done
# ============================================================
echo ""
echo "============================================================"
log "Cleanup complete."
echo ""
echo "  Next steps:"
echo "    1. Confirm kernel 6.18 is installed and GRUB is pinned:"
echo "       grep GRUB_DEFAULT /etc/default/grub"
echo "    2. Reboot into 6.18 if not already running it:"
echo "       uname -r"
echo "    3. Re-run setup.sh to reinstall ROCm cleanly on 6.18:"
echo "       sudo bash setup.sh <username>"
echo "============================================================"
echo ""
