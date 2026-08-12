# Development notes — hardware map and debugging history

Companion to `CLAUDE.md`. This file records *why* the driver looks the way it
does, so the same dead ends are not explored twice.

## Hardware map

```
USB 3.0 ──▶ FL2000DX ──┬── I²C master (regmap over USB control transfers)
                       │        │
                       │        ├── IT66121 HDMI bridge  @ 0x4C
                       │        └── monitor DDC/EDID     @ 0x50   ← EDID comes from here
                       │
                       ├── bulk EP1 OUT ── pixel stream ──▶ IT66121 ──▶ HDMI
                       │
                       ├── interrupt EP3 ── HPD / status events
                       │
                       └── mass storage function (virtual CD with Windows drivers)
```

The dongle additionally contains an unrelated **USB2 hub + C-Media audio chip**
that enumerate as their own USB devices.

Two things about this topology are counter-intuitive and cost a lot of time:

1. **The monitor's DDC lines hang off the FL2000 I²C bus (address 0x50), not off
   the IT66121's DDC master.** The IT66121 EDID FIFO path — which the in-tree
   `ite-it66121` driver uses, and which the original klogg driver implemented —
   never completes on this board. The vendor (Fresco) driver reads EDID at 0x50
   with the FL2000's own dword I²C engine, and that is what works here.
   `it66121_get_edid_block_direct()` implements it.

2. **The virtual CD-ROM function actively breaks the display.** `udisks` probes
   it, the storage function stops responding once the display driver resets the
   chip, and 30 s later the SCSI error handler issues `usb_reset_device()` on the
   *whole* device, tearing the display down. The `usb-storage` quirk
   (`1d5c:2000:i`) is not optional — see the README troubleshooting section, and
   note that `usb_storage` loads from the initramfs, so `mkinitcpio -P` is
   required after creating the modprobe.d file.

## Decoding the driver's DDC messages

`it66121_wait_ddc_ready()` logs the raw `IT66121_DDC_STATUS` (0x16) register:

| Bit | Mask | Meaning |
|-----|------|---------|
| 7 | 0x80 | TX done — the only reliable success signal |
| 6 | 0x40 | Engine active (transfer in progress) |
| 5 | 0x20 | NOACK — the target did not acknowledge |
| 4 | 0x10 | Waiting for bus |
| 3 | 0x08 | Arbitration lost |

Values seen in the field:

- `0x1A` (wait bus + arbitration lose, idle) — the DDC master cannot get the
  bus. Originally caused by the HDCP engine holding it after chip reset; fixed
  by restoring the ITE release sequence in `it66121_abort_ddc_ops()`.
- `0x4A` (active + arbitration lose) — the engine is running but keeps losing
  arbitration. On this board the FL2000 I²C master and the IT66121 DDC master
  share the physical bus, so **arbitration loss is a normal transient** caused
  partly by our own status polling. Do not treat error bits as fatal; wait for
  `TX_DONE` or the timeout, and poll sparsely.

`DDC not done (-110)` on the FIFO path followed by `EDID read ok` is the
**expected** sequence on this hardware: the FIFO attempt fails, the direct path
succeeds.

## Bug history (symptom → root cause)

Each of these was a real failure observed on hardware, in the order they were
found. All are fixed.

| Symptom | Root cause |
|---|---|
| Hard kernel hang on disconnect | `it66121_destroy()` → `component_del()` called from the master unbind callback, which already holds the global component mutex → self-deadlock |
| Display torn down ~30 s after every plug | SCSI timeout on the virtual CD → `usb_reset_device()` on the whole dongle |
| Driver never re-binds after a USB reset | Probe bailed out with `-ENODEV` because the bridge had been destroyed on disconnect while `devs` survived |
| `modprobe` appears to freeze the terminal | Probe runs synchronously in modprobe context while the device is stuck in the reset cycle; not a driver hang. Load the module with the adapter unplugged, then plug it (probe runs in a udev worker) |
| Only fallback modes (1024x768…), EDID empty | `drm_get_edid()` on the FL2000 I²C bus hit the adapter's 1-byte-read quirks (`msg too long (addr 0x0050)`). The 6.x modernization had replaced the working DDC-FIFO reader with it |
| EDID reads failing silently | No error logging anywhere in the DDC path; added logging first, then fixed the actual failures |
| `DDC not ready`, status `0x1A` | HDCP engine holding the DDC bus after chip reset; the original driver had deleted the ITE release sequence as "HDCP is not supported" |
| `DDC ... 0x4A`, EDID still failing | Fail-fast on error bits aborted healthy transfers on a shared, contended bus |
| Kernel Oops in `component_bind_all()` on rebind | Destroying/re-creating the component per bind cycle leaves dangling pointers in the aggregate match data |
| `failed to create dumb buffer: Cannot allocate memory` | GEM DMA (CMA) helpers require ~8.3 MB physically contiguous for 1080p; impossible on x86 without CMA. Switched to GEM SHMEM |
| Desktop-wide lag, amdgpu `Fence fallback timer expired` | Multi-MB `memcpy`/pixel conversion executed while holding `list_lock`, which disables interrupts. The resend copy runs continuously even on a static desktop |

## Rejected theories

- *"Kernel 7.x broke the DRM API broadly."* It did not. Almost everything the
  driver uses still exists in 7.1 (`drm_simple_display_pipe`, legacy bridge
  callbacks, `drm_get_edid`, `create_workqueue`, `REGCACHE_RBTREE`). The only
  mandatory change was bridge refcounting.
- *"The hardware or the monitor is faulty."* The same adapter and monitor work
  under Windows; every failure was driver-side.
- *"The EDID FIFO path just needs better timing."* It never completes on this
  board regardless of timing; the wiring is different (see Hardware map).

## Verifying kernel APIs

`git.kernel.org` blocks automated fetches (Anubis). Use the GitHub mirror:

```
https://raw.githubusercontent.com/torvalds/linux/v7.1/<path>
```

Download headers locally and grep them rather than trusting search results or
recollection — several of the fixes above came from reading
`drivers/base/component.c` and `drivers/gpu/drm/drm_bridge.c` directly.
