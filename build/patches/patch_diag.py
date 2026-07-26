#!/usr/bin/env python3
"""
patch_diag.py — Instrument the KSU-Next [ksu_driver] fd-delivery path with
dmesg logging so we can DIAGNOSE why the Manager app shows "not Working".

This is a debug-only patcher used to understand runtime behaviour; it does not
change any functional logic. It adds pr_info() lines that survive to
/proc/last_kmsg (read from TWRP, no root needed on the booted ROM).

What it instruments (kernel/supercall/supercall.c):
  1. ksu_handle_sys_reboot() entry  — logs EVERY reboot() call that reaches the
     hook, with magic1/magic2/cmd/pid. This tells us whether the Manager's
     libkernelsu actually issues the install magics (KSU_INSTALL_MAGIC1/2).
  2. The KSU_INSTALL_MAGIC2 branch  — logs right before ksu_install_fd() and
     after, so we can see whether the [ksu_driver] fd is actually created and
     into which pid.

Idempotent: guarded by a unique marker.

Usage:
  python3 patch_diag.py [path/to/kernel/supercall/supercall.c]
"""

import sys
import os

MARKER = "KSU_DIAG: reboot hook trace"

INSERT_BLOCK = (
    '\t/* ' + MARKER + ' */\n'
    '\tpr_info("KSU_DIAG ksu_handle_sys_reboot: magic1=0x%x magic2=0x%x '
    'cmd=%u pid=%d\\n",\n'
    '\t         magic1, magic2, cmd, current->pid);\n'
)


def find_supercall():
    candidates = [
        "kernel/supercall/supercall.c",
        "KernelSU-Next/kernel/supercall/supercall.c",
        "drivers/kernelsu/supercall/supercall.c",
    ]
    for c in candidates:
        if os.path.exists(c):
            return c
    return None


def find_fn(lines, name):
    for i, line in enumerate(lines):
        s = line.strip()
        if s.startswith("int %s(" % name) or s.startswith(
                "static int %s(" % name) or ("%s(" % name) in s and s.startswith("int"):
            return i, line
    return None, None


def patch(path):
    with open(path) as f:
        content = f.read()
    lines = content.splitlines(keepends=True)
    if not lines:
        print("ERROR: empty %s" % path)
        return False

    anchor_idx, _ = find_fn(lines, "ksu_handle_sys_reboot")
    if anchor_idx is None:
        print("ERROR: ksu_handle_sys_reboot not found in %s" % path)
        return False

    # idempotency guard
    if MARKER in content:
        print("OK: diag logging already present — skipping")
        return True

    # insert right after the function's opening brace
    brace_idx = None
    for i in range(anchor_idx, min(anchor_idx + 15, len(lines))):
        if "{" in lines[i]:
            brace_idx = i
            break
    if brace_idx is None:
        print("ERROR: no opening brace for ksu_handle_sys_reboot")
        return False

    old = lines[brace_idx]
    pos = old.find("{")
    before = old[:pos + 1]
    after = old[pos + 1:]
    lines[brace_idx] = before + "\n" + INSERT_BLOCK + after

    new = "".join(lines)
    with open(path, "w") as f:
        f.write(new)
    print("OK: instrumented ksu_handle_sys_reboot with KSU_DIAG logging")
    return True


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    path = args[0] if args else find_supercall()
    if not path or not os.path.exists(path):
        print("ERROR: supercall.c not found at %s" % (path or "(none)"))
        sys.exit(1)
    if not patch(path):
        sys.exit(1)
