#!/bin/bash
set -e

DRIVER_DIR="$(cd "$(dirname "$0")" && pwd)"
KERNEL_VERSION=$(uname -r)
MODULE_DIR="/lib/modules/${KERNEL_VERSION}/extra"

echo "=== FL2000 DRM Driver Installation Script ==="
echo "Kernel version: ${KERNEL_VERSION}"
echo "Driver directory: ${DRIVER_DIR}"

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)"
   exit 1
fi

echo ""
echo "=== Compiling driver ==="
cd "${DRIVER_DIR}"
make clean
make KVER="${KERNEL_VERSION}"

if [ ! -f "fl2000.ko" ]; then
    echo "ERROR: Module compilation failed"
    exit 1
fi

echo ""
echo "=== Checking Secure Boot status ==="
SB_ENABLED=0
if [ -d "/sys/firmware/efi" ]; then
    if mokutil --sb-state 2>/dev/null | grep -q "enabled"; then
        SB_ENABLED=1
        echo "Secure Boot is ENABLED - modules will be signed"
    else
        echo "Secure Boot is DISABLED - modules will not be signed"
    fi
else
    echo "Not a UEFI system - Secure Boot not applicable"
fi

echo ""
echo "=== Installing modules ==="
mkdir -p "${MODULE_DIR}"
cp -v fl2000.ko "${MODULE_DIR}/"
depmod -a

if [ ${SB_ENABLED} -eq 1 ]; then
    echo ""
    echo "=== Signing modules for Secure Boot ==="
    
    if [ ! -f "/var/lib/dkms/mok.key" ] && [ ! -f "/etc/mok.key" ]; then
        echo "No signing key found. Generating a new signing key..."
        
        if [ ! -d "/var/lib/dkms" ]; then
            mkdir -p /var/lib/dkms
        fi
        
        openssl req -new -x509 -newkey rsa:2048 -keyout /var/lib/dkms/mok.key \
            -out /var/lib/dkms/mok.pub -days 3650 -nodes -subj \
            "/CN=FL2000 Driver/"
        
        echo "Key generated at /var/lib/dkms/mok.key"
    fi
    
    MOK_KEY="/var/lib/dkms/mok.key"
    MOK_CERT="/var/lib/dkms/mok.pub"
    
    if [ -f "${MOK_KEY}" ] && [ -f "${MOK_CERT}" ]; then
        echo "Signing modules with existing key..."
        /usr/bin/sign-file sha256 "${MOK_KEY}" "${MOK_CERT}" "${MODULE_DIR}/fl2000.ko"
        
        echo "Modules signed successfully"
    else
        echo "WARNING: Could not sign modules - they may not load with Secure Boot enabled"
        echo "To sign manually, run:"
        echo "  sudo /usr/bin/sign-file sha256 /path/to/mok.key /path/to/mok.cert ${MODULE_DIR}/fl2000.ko"
    fi
fi

echo ""
echo "=== Reloading module dependencies ==="
depmod -a

echo ""
echo "=== Loading driver ==="
modprobe -r fl2000 2>/dev/null || true
modprobe fl2000 || echo "Note: Module loaded but device may not be connected"

echo ""
echo "=== Checking module status ==="
lsmod | grep fl2000 || echo "Module not loaded"
dmesg | tail -10 | grep fl2000 || echo "No driver messages in dmesg"

echo ""
echo "=== Installation complete ==="
echo ""
echo "To verify the driver is working:"
echo "  1. Connect a FL2000 USB display adapter"
echo "  2. Check 'dmesg' for driver messages"
echo "  3. Check /dev/dri/ for the DRM device"
echo ""
echo "To manually load the driver:"
echo "  sudo modprobe fl2000"
echo ""
echo "To remove the driver:"
echo "  sudo modprobe -r fl2000"
echo "  sudo rm -f ${MODULE_DIR}/fl2000.ko"
echo "  sudo depmod -a"