---
name: diagnose-cert-validation-on-rtcless-pi4
description: Fix 'certificate is not yet valid' errors on Pi4 and other RTC-less embedded systems by diagnosing system clock skew and enabling time synchronization
pattern_type: error_resolution
learned_at: 2026-06-23T11:06:31
source_session: 4427524e-b088-47e7-8398-6c34f88071ef
---

## When to use
When TLS/certificate validation fails with `certificate is not yet valid` on headless Pi4 or other embedded systems without RTC (real-time clock + battery).

## How
1. **Check system clock first** — not a missing SSL library issue. This error means the device's clock is set to a time *before* the certificate's `notBefore` date (valid-from).
   ```bash
   date  # System time
   systemctl status systemd-timesyncd  # Check if NTP is running
   timedatectl  # Full time/NTP status
   ```

2. **For immediate fix**: Synchronize the clock (either via NTP or manually).
   ```bash
   sudo timedatectl set-ntp true
   sleep 10 && timedatectl  # Wait for sync
   # OR manually if no NTP:
   sudo timedatectl set-time "2026-06-23 11:10:00"
   ```

3. **Diagnose root cause in Yocto image**: Pi4 loses power → forgets time → boots to old date. Check if image has time sync services.
   ```bash
   grep -rniE 'timesyncd|chrony|ntp|fake-hwclock' --include="*.bb" --include="*.conf" .
   # Should find references to systemd-timesyncd and/or fake-hwclock
   ```
   If nothing found, image is missing time sync — needs patch.

4. **Root fix**: Enable systemd-timesyncd + fake-hwclock in Yocto image (see separate skill).

## Why
Pi4 has no RTC chip + coin-cell battery. On cold boot, Linux uses a fallback date (often 1970 or whatever's in `/var/lib/systemd/timesync/clock`). If that's before cert `notBefore`, TLS stack correctly rejects the cert — not a bug, a feature.

## Example
User reported `certificate is not yet valid` when calling OpenAI API from opencode on Pi4. System clock was in the past due to cold boot + missing NTP in image. Fixed by enabling `systemd-timesyncd` in omelet-image.bb.
