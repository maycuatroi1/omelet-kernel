---
name: yocto-pi4-systemd-timesyncd-setup
description: Configure systemd-timesyncd and fake-hwclock in Omelet Pi4 Yocto image to persist clock across reboots
pattern_type: project_specific
learned_at: 2026-06-23T11:06:31
source_session: 4427524e-b088-47e7-8398-6c34f88071ef
---

## When to use
When building Omelet Pi4 Yocto image, to ensure clock stays synchronized after boot and persists across power cycles (mitigating Pi4's lack of RTC battery).

## How
1. **Verify systemd is the init manager** — already configured in omelet.conf:
   ```
   INIT_MANAGER = "systemd"
   ```

2. **Add systemd-timesyncd to image recipe** in `meta-omelet/recipes-core/images/omelet-image.bb`:
   ```bitbake
   IMAGE_INSTALL:append = " systemd-timesyncd fake-hwclock"
   ```
   (systemd-timesyncd handles NTP sync; fake-hwclock stores the system clock to disk on shutdown and restores it on boot, giving a "close enough" time even if offline.)

3. **Enable the service** (optional, usually auto-started by systemd on install):
   ```bash
   # After flashing, on the Pi itself:
   sudo systemctl enable systemd-timesyncd
   sudo systemctl start systemd-timesyncd
   ```

4. **Verify** on Pi:
   ```bash
   systemctl status systemd-timesyncd
   timedatectl
   # Should show "System clock synchronized: yes" after NTP contact
   ```

5. **Rebuild and flash**:
   ```bash
   ./scripts/build.sh  # Rebuilds image with timesyncd + fake-hwclock
   # Then flash to Pi
   ```

## Why
- **systemd-timesyncd**: Built into systemd, lightweight, no extra daemon overhead. Pulls time from NTP servers when network is up.
- **fake-hwclock**: Reads `/var/lib/systemd/timesync/clock` (last-known-good timestamp) on boot, so Pi wakes up close to real time even if offline. Prevents cold-boot time skew that breaks TLS.
- Together they handle both cases: online (NTP keeps it fresh) and offline (fake clock prevents multi-year resets).

## Example
Omelet Pi4 image was missing time sync → opencode chats failed with cert validation errors on cold boot → added `systemd-timesyncd fake-hwclock` to omelet-image.bb → rebuild + flash → problem solved.
