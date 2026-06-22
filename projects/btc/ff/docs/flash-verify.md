# Post-flash verification guide

Run **one** of the following on the device after the first boot completes.

**Direct from host (recommended):**
```bash
adb shell "sh -s docs/postflash_smoke.sh"
```

**On-device (if ADB is unavailable):**
```bash
adb push docs/postflash_smoke.sh /data/local/tmp/
adb shell "su -c sh /data/local/tmp/postflash_smoke.sh"
```

Expected outcome: all 10 checks show `PASS`, `RESULT: 10 passed, 0 failed`.

If any check shows `FAIL`, roll back immediately:
```bash
adb reboot bootloader
fastboot flash boot boot_backup_v2.2.img
fastboot reboot
```

---

## Checks in detail

The smoke script covers the same table as spec Â§5.7:

| # | Command | Expected value | Pass |
|---|---------|---------------|------|
| 1 | `uname -r` | matches `*Unholy*KSUN*V3*` | âœ“ |
| 2 | `cat /proc/version` | contains `clang version 12.0.5 (â€¦r416183b)` | âœ“ |
| 3 | `ksud debug version` | `Kernel Version: 13000+` | âœ“ |
| 4 | `ksu_susfs show variant` | `NON-GKI` | âœ“ |
| 5 | `ksu_susfs show version` | `v1.5.5` | âœ“ |
| 6 | `ksu_susfs show enabled_features` | 14 lines | âœ“ |
| 7 | `sudo ksud module list` | JSON, 17 entries all `"enabled":true` | âœ“ |
| 8 | `pm path com.rifsxd.ksunext` | non-empty path under `/data/app/` | âœ“ |
| 9 | `pm dump com.rifsxd.ksunext` | versionCode=33129 (manager v3.2.0) | âœ“ |
| 10 | `dmesg | grep CMD_SUSFS_SHOW_VERSION` | present | âœ“ |

Checks 1â€“5 are the minimum to confirm the kernel swap succeeded.
Checks 6â€“10 confirm module / SUSFS state survived.

Mismatches are usually:
- **`ksud debug version` returns 0** â€” booted the old v2.2 boot (fastboot bootloader slot confused; re-flash explicitly the correct slot).
- **`susfs version` returns `v1.5.5`** â€” that's actually the expected value for this build; `v1.5.5` is the
  latest SUSFS that supports 4.14 NON-GKI. v2.x is GKI-only and breaks on this tree.
- **`module list` returns fewer than 17** â€” modules that depend on Zygisk need `zygisk=true` in their `module.prop`; did not change. Re-list via `ksud module list --json`.
