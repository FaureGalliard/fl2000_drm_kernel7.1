# FL2000 USB Display Driver for Linux Kernel 7.x

<p align="center">
  <img src="https://img.shields.io/badge/License-GPL%20v2-blue.svg" alt="License">
  <img src="https://img.shields.io/badge/Kernel-6.16%2B%20%2F%207.x-green.svg" alt="Kernel Version">
  <img src="https://img.shields.io/badge/Architecture-x86__64-orange.svg" alt="Architecture">
</p>

## Overview

This is a modernized version of the FL2000 DRM driver, updated to work with Linux kernel 7.x (also builds on kernel 6.16 and later). The driver supports USB-to-HDMI adapters based on the Fresco Logic FL2000DX chip with the IT66121FN HDMI bridge.

## Features

- **Modern DRM API**: Updated to use current kernel 6.x DRM APIs
- **Atomic Modesetting**: Full support for atomic display configuration
- **Automatic Resolution**: Dynamically adjusts based on USB bandwidth
- **Secure Boot Ready**: Built-in module signing support
- **Plug & Play**: Automatic device detection
- **Triple Buffering**: Smooth rendering with multiple buffers

## Hardware Compatibility

| Device | Chipset | Max Resolution |
|--------|---------|----------------|
| USB HDMI Dongle | FL2000DX + IT66121FN | 4K@30Hz (USB 3.0), 1080p@60Hz |

- **USB 2.0**: Up to 1080p@30Hz
- **USB 3.0**: Up to 4K@30Hz or 1080p@60Hz

## Requirements

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install build-essential linux-headers-$(uname -r)

# Verify kernel version (must be 6.16 or later, including 7.x)
uname -r
```

## Installation

### Quick Install (Recommended)

```bash
cd /home/samuel/driver/fl2000_drm
sudo ./install.sh
```

The installation script will:
1. Compile the driver for your kernel
2. Detect Secure Boot status
3. Sign modules if required
4. Install modules to the system
5. Load the driver

### Manual Installation

```bash
# Compile
make clean
make KVER=$(uname -r)

# Install (as root)
sudo cp fl2000.ko it66121.ko /lib/modules/$(uname -r)/extra/
sudo depmod -a

# Load
sudo modprobe fl2000
```

### Secure Boot Setup

If Secure Boot is enabled, the driver needs to be signed:

```bash
# Generate signing keys (one-time setup)
sudo openssl req -new -x509 -newkey rsa:2048 \
  -keyout /var/lib/dkms/mok.key \
  -out /var/lib/dkms/mok.pub \
  -days 3650 -nodes \
  -subj "/CN=FL2000 Driver/"

# Sign modules
sudo /usr/bin/sign-file sha256 /var/lib/dkms/mok.key \
  /var/lib/dkms/mok.pub /lib/modules/$(uname -r)/extra/fl2000.ko

# Import key for next boot
sudo mokutil --import /var/lib/dkms/mok.pub
```

## Verification

```bash
# Check module loaded
lsmod | grep fl2000

# Check driver messages
dmesg | grep -i fl2000

# List DRM devices
ls -la /dev/dri/

# Get device info
cat /sys/class/drm/*/device/name
```

## Project Structure

```
fl2000_drm/
├── fl2000.h              # Main header file
├── fl2000_drv.c          # USB driver core
├── fl2000_drm.c          # DRM implementation
├── fl2000_streaming.c    # USB streaming
├── fl2000_i2c.c          # I2C interface
├── fl2000_interrupt.c    # Interrupt handling
├── fl2000_registers.c   # Hardware registers
├── bridge/
│   ├── it66121.h         # Bridge header
│   ├── it66121_drv.c     # IT66121 bridge driver
│   └── it66121_registers.h
├── Makefile              # Build system
├── install.sh            # Installation script
└── README.md             # This file
```

## Troubleshooting

### Adapter disconnects ~30 seconds after plugging in

These dongles expose a virtual CD-ROM (mass storage, `/dev/sr0`) with Windows
drivers alongside the display interfaces. When the display driver initializes
the chip, the storage function can stop responding; the SCSI layer then times
out (30 s) and issues a USB reset of the whole device, which unbinds the
display driver. Tell the kernel to ignore the storage function:

```bash
# Make usb-storage ignore the FL2000 virtual CD-ROM (takes effect on next plug)
echo 'options usb-storage quirks=1d5c:2000:i' | sudo tee /etc/modprobe.d/fl2000-storage.conf
sudo modprobe -r usb_storage 2>/dev/null; sudo modprobe usb_storage

# Or apply immediately without reloading modules:
echo '1d5c:2000:i' | sudo tee /sys/module/usb_storage/parameters/quirks
```

The virtual CD only contains Windows/Mac drivers, so nothing is lost.

### Driver won't load

1. Check kernel headers installed:
   ```bash
   ls /lib/modules/$(uname -r)/build
   ```

2. Check error messages:
   ```bash
   dmesg | tail -50
   ```

3. Verify USB device connected:
   ```bash
   lsusb | grep -i fresco
   ```

### No display output

1. Check EDID reading:
   ```bash
   dmesg | grep -i edid
   ```

2. Verify monitor detection:
   ```bash
   cat /sys/class/drm/card1-*/status
   ```

3. Try manual mode setting:
   ```bash
   xrandr --output DP-1 --auto
   ```

## Known Issues

- Audio over HDMI not implemented (video only)
- Multiple adapters untested
- Limited to single display per adapter

## License

GPL v2 - See [LICENSE](./LICENSE) file for details.

## Contributors

### Original Project
- **Marcus Comstedt** (@zeldin) - Original driver development
- **Marcel Waldvogel** (@MarcelWaldvogel) - Driver improvements
- **Artem Mygaiev** - Original DRM driver implementation and maintainer

### Kernel 6.x Modernization (2026)
- **Samuel** - Used original code and updated for Linux Kernel 6.x

### What Was Done

#### Port to Kernel 7.x (July 2026):
1. **Refcounted DRM bridges** (mandatory since kernel 6.16/7.x)
   - IT66121 bridge is now allocated with `devm_drm_bridge_alloc()` instead of
     `kzalloc()`; its lifetime is managed by the DRM core reference counting
   - Removed manual `kfree()` of the bridge private structure (freed by the
     bridge release once the last reference is dropped)
2. **Fixed DRM device teardown for hot-unplug**
   - Fixed kernel deadlock on disconnect: `it66121_destroy()` calls
     `component_del()`, which takes the global component mutex — but it was
     invoked from the master unbind callback, which already runs with that
     mutex held (`component_master_del()` → unbind). It is now called from
     `fl2000_disconnect()` after `component_master_del()` returns
   - `drm_dev_unplug()` + `drm_atomic_helper_shutdown()` now run on unbind,
     before components are detached (same pattern as in-tree USB display
     drivers such as gm12u320)
   - Removed double `drm_mode_config_cleanup()` (already managed by
     `drmm_mode_config_init()`) and a double `drm_dev_put()` (already managed
     by `devm_drm_dev_alloc()`), both of which caused use-after-free on
     disconnect
   - Fixed unbind devres pairing so the teardown callback actually runs
3. **Fixes found during the port**
   - EDID reads no longer dereference a NULL I2C adapter
     (`priv->adapter` was never assigned)
   - Interrupt polling work is initialized once at bridge creation, so
     `cancel_delayed_work_sync()` can no longer touch an uninitialized work
4. **Build system**
   - Replaced deprecated `EXTRA_CFLAGS` with `ccflags-y`

#### Modernization for Kernel 6.x:
1. **Updated DRM Headers**
   - Removed deprecated headers (`drm_fbdev_generic.h`, `drm_crtc_helper.h`, `drm_ioctl.h`)
   - Added modern DRM headers (`drm_device.h`, `drm_client.h`, `drm_damage_helper.h`)

2. **Fixed Deprecated API Calls**
   - Changed `lastclose` → `postclose` in `drm_driver`
   - Updated `it66121_bridge_attach()` signature to include encoder parameter
   - Changed `drm_helper_hpd_irq_event()` → `drm_bridge_hpd_notify()`
   - Replaced `drm_do_get_edid()` with `drm_get_edid()`

3. **Added Secure Boot Support**
   - Created `install.sh` script with automatic module signing
   - MOK key generation and enrollment support

4. **Documentation**
   - Improved README.md with installation instructions
   - Created comprehensive GitHub Wiki with technical details
   - Added troubleshooting guides

#### Removed/Disabled Features:
- `drm_kms_helper_poll_init/fini` - Not needed in modern kernels
- `drm_plane_enable_fb_damage_clips` - Not compatible
- `drm_fbdev_generic_setup` - Removed (fbdev emulation is deprecated)
- `drm_atomic_helper_damage_merged` - Compatibility issues

## Links

- [GitHub Wiki](https://github.com/Samuv5/fl2000_drm/wiki) - Detailed technical documentation
- [Original Repository](https://github.com/klogg/fl2000_drm)
- [Linux DRM Documentation](https://www.kernel.org/doc/html/latest/gpu/drm-kms-helpers.html)

---

*For detailed technical documentation, see [WIKI.md](./WIKI.md)*