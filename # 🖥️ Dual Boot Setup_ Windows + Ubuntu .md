# 🖥️ Dual Boot Setup: Windows + Ubuntu 24.04 (ROCm + Docker + Ollama)

This guide is designed for technicians to set up a new machine for GPU-based AI workloads.

---

# 🔹 1. Windows Initial Setup

## Bypass Microsoft Account

During Windows setup:

* Click **"I can’t connect to the network"**
* Proceed with a **local account** without having to create microsft account

---
## Disable Windows Fast Startup (if dual booting with Windows):

Run as Administrator in command prompt 
`powercfg /h off`

or

Control Panel → Power Options → "Choose what the power buttons do" → uncheck Turn on fast startup

## Disable BitLocker

1. Open **Settings**
2. Go to **Privacy & Security → Device Encryption / BitLocker**
3. Turn **OFF BitLocker**
4. Wait until decryption completes (5-7mins)

---

## BIOS - Disable Secure Boot

### Enter BIOS

Restart and press repeatedly:

```
F10 
```

### In BIOS

* Find **Secure Boot**
* Set to **Disabled**
* Save & Exit

---

# 🔹 2. Install Ubuntu 24.04 (Dual Boot)

## Create Bootable USB

* Download Ubuntu 24.04 ISO
* Use **Rufus** or **Balena Etcher** to create USB

---

## Install Ubuntu

1. Boot from USB
2. Select **Install Ubuntu**
3. Choose Dual Boot option ( Install alongside Windows)
4. COnnect to Wifi: `AMD GUEST`

### Partition

* Allocate **1 TB** for Ubuntu

### Credentials

```
Username: amd-user
Password: amd1234
```

Reboot after installation.

---

# 🔹 3. Configure GRUB (GPU Stability Fix)

## Create config file

```bash
sudo vi /etc/default/grub.d/amd_cwsr.cfg
```

## Add this line

```bash
GRUB_CMDLINE_LINUX="${GRUB_CMDLINE_LINUX:+$GRUB_CMDLINE_LINUX }amdgpu.cwsr_enable=0"
```

## Update GRUB

```bash
sudo update-grub
```



# 🔹 4. Run Setup Script

Run:

```bash
sudo bash setup.sh amd-user
```
# 🔹 4. Run Important dkms
```bash
sudo apt autoremove amdgpu-dkms dkms
sudo usermod -a -G render,video $LOGNAME
```

## Reboot

```bash
sudo reboot
```

---


## This installs:

* Git
* Docker
* VS Code
* ROCm 7.2

---

# 🔹 5. Docker Setup

## Pull Image

```bash
docker pull rocm/vllm-dev:rocm7.2.1_navi_ubuntu24.04_py3.12_pytorch_2.9_vllm_0.16.0
```

## Run Container

```bash
docker run -it \
  --privileged \
  --device=/dev/kfd \
  --device=/dev/dri \
  --network=host \
  --group-add sudo \
  -w /app/workshop/ \
  --name workshop_env \
  rocm/vllm-dev:rocm7.2.1_navi_ubuntu24.04_py3.12_pytorch_2.9_vllm_0.16.0 \
  /bin/bash
```

---

# 🔹 6. Install Ollama

```bash
curl -fsSL https://ollama.com/install.sh | sh
```

---

# 🔹 7. (Optional but Recommended) Verify GPU

Run:

```bash
rocminfo
```

```bash
rocm-smi
```

---

# ⚠️ Troubleshooting

## If GPU is NOT detected:

* Ensure Secure Boot is disabled
* Ensure BIOS virtualization (SVM) is enabled
* Reboot after ROCm install

---

# ✅ Setup Complete

You now have:

* Windows + Ubuntu dual boot
* ROCm GPU support
* Docker AI environment
* Ollama for local LLMs

---
