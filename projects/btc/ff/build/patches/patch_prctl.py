#!/usr/bin/env python3
"""
Patch kernel/sys.c to intercept prctl(option=0xDEADBEEF, ...) syscalls.

Handles TWO dispatch targets:

  (a) KSU GET_INFO (arg2 == 2) — legacy prctl-based detection path used by
      the KernelSU-Next Manager's native lib (libkernelsu.so) as a fallback
      in legacy_get_info(). Returns KSU version & flags so the Manager shows
      "Working" instead of "Unsupported | Not integrated".

  (b) SUSFS command dispatch (arg2 = CMD_SUSFS_*) — routes to
      susfs_handle_sys_reboot(arg2, (void __user *)arg3) so the ksu_susfs
      userspace binary (which calls prctl(0xDEADBEEF, ...)) gets service.

Background:
  The Manager's libkernelsu.so calls prctl(0xDEADBEEF, 2, &ver, &flags, &err)
  before giving up. Without handler (a), the Manager shows "Unsupported" even
  though KSU is compiled in and working — the Manager's ioctl path needs
  the [ksu_driver] fd which is per-process and O_CLOEXEC.

Usage:
  python3 patch_prctl.py [--ksu-dir <path>] [path/to/kernel/sys.c]

  --ksu-dir  : path to KernelSU-Next git clone (for KSU_VERSION calculation).
               Default: "KernelSU-Next" (relative to cwd).
               Omit or set empty to skip version from git (uses fallback).
"""

import sys
import os
import subprocess


# ── KSU version detection ──────────────────────────────────────────────────────

# Fallback: used when KSUN git repo isn't reachable
FALLBACK_KSU_VERSION = 33186  # last known good value for legacy branch


def get_ksu_version(ksu_dir):
    """
    Compute KSU_VERSION from KSUN's git commit count.

    Kbuild calculates it as: 30000 + $(git rev-list --count HEAD) + 200
    """
    if not ksu_dir:
        print(f"WARNING: no --ksu-dir given, using fallback KSU_VERSION={FALLBACK_KSU_VERSION}")
        return FALLBACK_KSU_VERSION

    if not os.path.isdir(ksu_dir):
        print(f"WARNING: --ksu-dir '{ksu_dir}' not found, using fallback KSU_VERSION={FALLBACK_KSU_VERSION}")
        return FALLBACK_KSU_VERSION

    git_dir = os.path.join(ksu_dir, ".git")
    if not os.path.exists(git_dir):
        print(f"WARNING: '{ksu_dir}' is not a git repo (no .git), using fallback KSU_VERSION={FALLBACK_KSU_VERSION}")
        return FALLBACK_KSU_VERSION

    try:
        result = subprocess.run(
            ["git", "rev-list", "--count", "HEAD"],
            cwd=ksu_dir,
            capture_output=True,
            text=True,
            timeout=10,
        )
        if result.returncode != 0:
            print(f"WARNING: git rev-list failed: {result.stderr.strip()}, using fallback")
            return FALLBACK_KSU_VERSION

        count = int(result.stdout.strip())
        version = 30000 + count + 200
        print(f"OK: KSU_VERSION = 30000 + {count} + 200 = {version} (from {ksu_dir})")
        return version
    except Exception as e:
        print(f"WARNING: could not read KSU version: {e}, using fallback {FALLBACK_KSU_VERSION}")
        return FALLBACK_KSU_VERSION


# ── Kernel source patching ─────────────────────────────────────────────────────

def find_prctl_anchor_line(lines):
    """
    Find the line index of the prctl syscall definition.
    Returns (line_idx, line) or (None, None).
    Handles both SYSCALL_DEFINE5 and SYSCALL_DEFINE3 variants,
    including multi-line macro invocations (common on CAF kernels).
    """
    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("SYSCALL_DEFINE5(prctl,") or stripped.startswith("SYSCALL_DEFINE3(prctl,"):
            return i, line
        if "SYSCALL_DEFINE5(prctl, int, option" in stripped:
            return i, line
        if "SYSCALL_DEFINE3(prctl, int, option" in stripped:
            return i, line
        if "asmlinkage long sys_prctl(int option" in stripped:
            return i, line
    return None, None


def find_fn_brace(lines, anchor_idx):
    """
    Find the opening brace '{' of the function body.
    Search from anchor_idx through continuation lines until we find '{'.
    Returns the index of the line containing '{', or None.
    """
    for i in range(anchor_idx, min(anchor_idx + 10, len(lines))):
        stripped = lines[i].strip()
        if '{' in stripped:
            return i
        if i > anchor_idx and stripped.startswith("SYSCALL_DEFINE"):
            return None
    return None


def build_ksu_block(ksu_version):
    """
    Build the KSU+SUSFS dispatch block with the computed version number.
    """
    return (
        '\t/* KSU + SUSFS command dispatch via prctl syscall */\n'
        '\tif (unlikely(option == 0xDEADBEEF)) {\n'
        '\t\t/* KSU GET_INFO: Manager legacy_get_info() fallback */\n'
        '\t\tif (arg2 == 2) {\n'
        f'\t\t\tint32_t ver = {ksu_version};\n'
        '\t\t\tint32_t flags = 0;\n'
        '\t\t\tint32_t err = 0;\n'
        '\t\t\tif (copy_to_user((void __user *)arg3, &ver, sizeof(ver)))\n'
        '\t\t\t\treturn -EFAULT;\n'
        '\t\t\tif (copy_to_user((void __user *)arg4, &flags, sizeof(flags)))\n'
        '\t\t\t\treturn -EFAULT;\n'
        '\t\t\tif (copy_to_user((void __user *)arg5, &err, sizeof(err)))\n'
        '\t\t\t\treturn -EFAULT;\n'
        '\t\t\treturn 0;\n'
        '\t\t}\n'
        '\t\t/* SUSFS command dispatch */\n'
        '\t\textern int susfs_handle_sys_reboot(unsigned int cmd, void __user *arg);\n'
        '\t\treturn susfs_handle_sys_reboot((unsigned int)arg2, (void __user *)arg3);\n'
        '\t}\n'
        '\n'
    )


def already_has_both_handlers(brace_content):
    """Check if both KSU GET_INFO and SUSFS handlers are already present."""
    has_ksu = 'arg2 == 2' in brace_content and 'KSU GET_INFO' in brace_content
    has_susfs = '0xDEADBEEF' in brace_content and 'susfs_handle_sys_reboot' in brace_content
    return has_ksu and has_susfs


def already_has_susfs_only(brace_content):
    """Check if only the SUSFS handler is present (old format)."""
    return '0xDEADBEEF' in brace_content and 'susfs_handle_sys_reboot' in brace_content


def patch_prctl(path, ksu_version):
    """Insert KSU GET_INFO + SUSFS dispatch at the top of SYSCALL_DEFINE5(prctl,...)."""

    with open(path) as f:
        content = f.read()

    lines = content.splitlines(keepends=True)
    if not lines:
        print(f"ERROR: empty file {path}")
        return False

    anchor_idx, anchor_line = find_prctl_anchor_line(lines)
    if anchor_idx is None:
        print(f"ERROR: could not find prctl syscall anchor in {path}")
        return False

    brace_idx = find_fn_brace(lines, anchor_idx)
    if brace_idx is None:
        print(f"WARNING: could not find opening brace after SYSCALL_DEFINE at line {anchor_idx+1}, trying fallback...")
        combined = ""
        for i in range(anchor_idx, min(anchor_idx + 10, len(lines))):
            combined += lines[i]
            if combined.strip().endswith(')') or ')' in combined:
                for j in range(i + 1, min(i + 5, len(lines))):
                    if '{' in lines[j]:
                        brace_idx = j
                        break
                if brace_idx:
                    break

    if brace_idx is None:
        print(f"ERROR: could not locate function body opening brace after prctl SYSCALL_DEFINE (anchor line {anchor_idx+1})")
        print(f"  Anchor text: {anchor_line.strip()}")
        print(f"  Following lines:")
        for k in range(anchor_idx, min(anchor_idx + 8, len(lines))):
            print(f"    {k+1}: {lines[k].rstrip()}")
        return False

    print(f"Found prctl SYSCALL_DEFINE at line {anchor_idx+1}, body brace at line {brace_idx+1}")

    # Check what's currently in the function top
    search_end = min(brace_idx + 40, len(lines))
    func_top = ''.join(lines[brace_idx:search_end])

    ksu_block = build_ksu_block(ksu_version)

    if already_has_both_handlers(func_top):
        print("OK: KSU GET_INFO + SUSFS dispatch already present — skipping injection")
        return True

    if already_has_susfs_only(func_top):
        print("NOTE: old SUSFS-only prctl block found — replacing with KSU+SUSFS block")
        # Find and remove the old SUSFS block
        # The old block starts with the 0xDEADBEEF if and ends at the blank line
        # We need to calculate line ranges carefully
        old_start = func_top.find('\t/* SUSFS')
        old_end = func_top.find('\n', old_start)
        if old_start < 0:
            # Try finding by comment marker
            old_start = func_top.find('\t/* SUSFS command dispatch')
        if old_start >= 0:
            # Find the end: after the closing } and blank line
            search_from = old_start
            for scan_line_end in range(brace_idx, search_end):
                line = lines[scan_line_end]
                if '\t/* SUSFS' in line or '\t/* KSU + SUSFS' in line:
                    # Found the old block start - find its end
                    old_block_end = scan_line_end
                    # Scan for the end of the block (two consecutive newlines after closing })
                    closing_found = False
                    for sj in range(scan_line_end, min(scan_line_end + 20, len(lines))):
                        stripped = lines[sj].strip()
                        if stripped == '}':
                            closing_found = True
                        if closing_found and stripped == '':
                            old_block_end = sj + 1  # include the blank line
                            break
                    # Remove old block lines
                    for ri in range(old_block_end - 1, scan_line_end - 2, -1):
                        if ri >= 0:
                            del lines[ri]
                    print(f"  Removed old SUSFS block (lines {scan_line_end+1}-{old_block_end})")
                    break

    # Check if new block already exists (after possible removal above)
    func_top_after_removal = ''.join(lines[brace_idx:min(brace_idx + 10, len(lines))])

    # Insert the new block right after opening brace
    brace_pos_in_line = lines[brace_idx].find('{')
    if brace_pos_in_line < 0:
        print(f"ERROR: no '{{' found on line {brace_idx+1}: '{lines[brace_idx].strip()}'")
        return False

    old_line = lines[brace_idx]
    lines[brace_idx] = old_line[:brace_pos_in_line + 1] + '\n' + ksu_block + old_line[brace_pos_in_line + 1:]

    new_content = ''.join(lines)
    if new_content == content:
        print(f"ERROR: insert produced no change in {path}")
        return False

    with open(path, 'w') as f:
        f.write(new_content)

    print(f"OK: patched {path} with KSU+SUSFS prctl dispatch (KSU_VERSION={ksu_version})")
    return True


def main():
    ksu_dir = "KernelSU-Next"
    positional_args = []

    # Parse args
    remaining = sys.argv[1:]
    while remaining:
        arg = remaining.pop(0)
        if arg == "--ksu-dir":
            ksu_dir = remaining.pop(0) if remaining else None
        elif arg.startswith("--ksu-dir="):
            ksu_dir = arg.split("=", 1)[1]
        else:
            positional_args.append(arg)

    if len(positional_args) > 0:
        path = positional_args[0]
    else:
        path = find_sys_c()

    if not path or not os.path.exists(path):
        print(f"ERROR: kernel/sys.c not found at {path or '(none given)'}")
        print("Hint: run this script from the kernel source root directory")
        sys.exit(1)

    ksu_version = get_ksu_version(ksu_dir)

    if not patch_prctl(path, ksu_version):
        sys.exit(1)


def find_sys_c():
    candidates = ["kernel/sys.c"]
    for c in candidates:
        if os.path.exists(c):
            return c
    return None


if __name__ == "__main__":
    main()
