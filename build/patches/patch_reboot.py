#!/usr/bin/env python3
"""
Patch kernel/reboot.c to:
  (a) Inject ksu_handle_sys_reboot(...) call at the top of SYSCALL_DEFINE4(reboot)
      so KSUN's Kbuild hook check (grep for "ksu_handle_sys_reboot") passes.
  (b) Insert SUSFS magic2 == 0xFAFAFAFA dispatch after the KSUN call so
      SUSFS commands return 0 to userspace (instead of -EINVAL from the
      magic1/magic2 validation).

Rationale:
  The KSUN legacy branch's setup.sh does NOT add the manual hook call to
  kernel/reboot.c (it relies on kprobes by default).  For MANUAL_HOOK mode
  (required on < 5.10 to avoid the "KPROBES_HOOK should not be used on
  kernels below 5.10" restriction), the Kbuild check at line 149 greps for
  "ksu_handle_sys_reboot" in kernel/reboot.c and errors out if not found.

Usage: python3 patch_reboot.py [path/to/kernel/reboot.c]

If no path is given, searches for kernel/reboot.c in the cwd.
"""

import sys
import os


def find_reboot():
    """Find kernel/reboot.c relative to the current directory."""
    candidates = [
        "kernel/reboot.c",
        "kernel/sys.c",  # fallback
    ]
    for c in candidates:
        if os.path.exists(c):
            return c
    return None


def find_syscall_defn_line(lines, defn_name="reboot"):
    """
    Find the line index of SYSCALL_DEFINE4(reboot, ...).
    Returns (line_idx, line) or (None, None).
    """
    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith(f"SYSCALL_DEFINE4({defn_name},"):
            return i, line
        if stripped.startswith(f"SYSCALL_DEFINE3({defn_name},"):
            return i, line
        if f"SYSCALL_DEFINE4({defn_name}" in stripped:
            return i, line
        # asmlinkage variant (rare)
        if stripped.startswith(f"asmlinkage long sys_{defn_name}("):
            return i, line
    return None, None


def find_fn_brace(lines, anchor_idx, max_lookahead=20):
    """
    Find the opening brace '{' of the function body.
    Search from anchor_idx through continuation lines until we find '{'.
    Returns the index of the line containing '{', or None.
    """
    for i in range(anchor_idx, min(anchor_idx + max_lookahead, len(lines))):
        stripped = lines[i].strip()
        if '{' in stripped:
            return i
        # If we hit another SYSCALL_DEFINE, we went too far
        if i > anchor_idx and stripped.startswith("SYSCALL_DEFINE"):
            return None
    return None


# --- Blocks to inject (each as a list of separate lines, no embedded \\n) ---

KSUN_HOOK_LINES = [
    '\t/* KSUN manual hook \xe2\x80\x94 required by Kbuild hook check */\n',
    '\textern int ksu_handle_sys_reboot(int magic1, int magic2,\n',
    '\t\t\t\t   unsigned int cmd, void __user **arg);\n',
    '\tvoid __user *ksu_arg_ptr = arg;\n',
    '\tksu_handle_sys_reboot(magic1, magic2, cmd, &ksu_arg_ptr);\n',
]

SUSFS_DISPATCH_LINES = [
    '\n',
    '\t/* SUSFS command dispatch via reboot syscall magics */\n',
    '\tif (unlikely(magic2 == 0xFAFAFAFA)) {\n',
    '\t\textern int susfs_handle_sys_reboot(unsigned int cmd, void __user *arg);\n',
    '\t\treturn susfs_handle_sys_reboot(cmd, arg);\n',
    '\t}\n',
]


def insert_block_after_brace(lines, brace_idx, block_lines):
    """
    Insert block_lines as individual list entries right after the
    opening brace '{'.  Each entry in block_lines becomes its own
    line in the output (no embedded newlines within block entries).
    Returns the modified lines list.
    """
    old_line = lines[brace_idx]
    brace_pos = old_line.find('{')
    if brace_pos < 0:
        return None

    after_brace = old_line[brace_pos + 1:].lstrip('\n')

    # Replace the brace line: everything before brace + brace
    lines[brace_idx] = old_line[:brace_pos + 1] + '\n'

    # Insert block lines at brace_idx+1
    insert_pos = brace_idx + 1
    for i, bline in enumerate(block_lines):
        lines.insert(insert_pos + i, bline)

    # If there was content after the brace (e.g. '{ int x; }'), re-append it
    if after_brace.strip():
        lines.insert(insert_pos + len(block_lines), after_brace)

    return lines


def find_closing_brace(lines, start_idx, max_search=30):
    """
    Find the first standalone '}' (at column 0 after optional whitespace)
    within max_search lines.
    Returns the line index, or start_idx if not found.
    """
    for i in range(start_idx, min(start_idx + max_search, len(lines))):
        stripped = lines[i].strip()
        if stripped == '}':
            return i
        # Stop if we hit another control flow or declaration that suggests
        # the block ended before here
        if stripped.startswith('if ') or stripped.startswith('switch ') or stripped.startswith('case '):
            # Don't cross into unrelated control flow — the block is above
            if i > start_idx:
                return i - 1
    return start_idx  # fallback: insert at start_idx


def patch_reboot(path):
    """Insert KSUN manual hook + SUSFS dispatch at the top of SYSCALL_DEFINE4(reboot)."""

    with open(path) as f:
        content = f.read()

    lines = content.splitlines(keepends=True)
    if not lines:
        print(f"ERROR: empty file {path}")
        return False

    # ── 1. Find the function ──
    anchor_idx, anchor_line = find_syscall_defn_line(lines, "reboot")
    if anchor_idx is None:
        print(f"ERROR: could not find SYSCALL_DEFINE4(reboot, ...) in {path}")
        return False

    # ── 2. Find the opening brace ──
    brace_idx = find_fn_brace(lines, anchor_idx)
    if brace_idx is None:
        print(f"ERROR: could not find opening brace after SYSCALL_DEFINE4(reboot) at line {anchor_idx + 1}")
        print(f"  Anchor text: {anchor_line.strip()}")
        for k in range(anchor_idx, min(anchor_idx + 12, len(lines))):
            print(f"    {k + 1}: {lines[k].rstrip()}")
        return False

    print(f"Found SYSCALL_DEFINE4(reboot) at line {anchor_idx + 1}, body brace at line {brace_idx + 1}")

    modified = False

    # ── 3. Check if KSUN hook already exists ──
    search_end = min(brace_idx + 30, len(lines))
    func_top = ''.join(lines[brace_idx:search_end])
    has_ksun_hook = 'ksu_handle_sys_reboot' in func_top

    if not has_ksun_hook:
        result = insert_block_after_brace(lines, brace_idx, KSUN_HOOK_LINES)
        if result is None:
            print(f"ERROR: could not insert KSUN hook after brace at line {brace_idx + 1}")
            return False
        lines = result
        modified = True
        print("OK: injected KSUN manual hook call")
    else:
        print("OK: KSUN manual hook already present — skipping injection")

    # ── 4. Check if SUSFS dispatch already exists ──
    search_end_2 = min(brace_idx + 40, len(lines))
    func_top_2 = ''.join(lines[brace_idx:search_end_2])
    has_susfs = '0xFAFAFAFA' in func_top_2

    if not has_susfs:
        # Calculate where to insert the SUSFS dispatch:
        #   - If we just injected KSUN hook lines, the last KSUN line
        #     is at brace_idx + 1 + len(KSUN_HOOK_LINES) - 1
        #   - SUSFS goes right after that: brace_idx + 1 + len(KSUN_HOOK_LINES)
        #   - If KSUN was already present, look for a natural anchor
        #     near the function top (e.g. declaration or existing code)
        if not has_ksun_hook:
            # We injected KSUN → SUSFS goes right after it
            insert_after = brace_idx + 1 + len(KSUN_HOOK_LINES) - 1
        else:
            # KSUN existed; insert SUSFS after a reasonable offset
            # from the function top (after any existing KSUN code)
            closure_idx = find_closing_brace(lines, brace_idx + 1)
            if closure_idx == brace_idx + 1:
                insert_after = brace_idx + 2  # conservative: after first few decls
            else:
                insert_after = closure_idx

        # Insert SUSFS block at insert_after + 1
        susfs_pos = insert_after + 1
        for i, sline in enumerate(SUSFS_DISPATCH_LINES):
            lines.insert(susfs_pos + i, sline)
        modified = True
        print(f"OK: injected SUSFS dispatch after line {insert_after + 1}")
    else:
        print("OK: SUSFS dispatch already present — skipping injection")

    # ── 5. Write result ──
    if not modified:
        print("WARNING: no changes made — both blocks already present")
        return True  # Not an error

    new_content = ''.join(lines)
    with open(path, 'w') as f:
        f.write(new_content)
    print(f"Patched file written: {path}")
    return True


def verify_patch(path):
    """Verify both the KSUN hook and SUSFS dispatch are present."""
    with open(path) as f:
        content = f.read()
    ok = True

    if 'ksu_handle_sys_reboot' in content:
        print("VERIFY: KSUN manual hook found in kernel/reboot.c")
    else:
        print("VERIFY FAILED: KSUN manual hook NOT found in kernel/reboot.c")
        ok = False

    if '0xFAFAFAFA' in content and 'susfs_handle_sys_reboot' in content:
        print("VERIFY: SUSFS dispatch found in kernel/reboot.c")
    else:
        print("VERIFY FAILED: SUSFS dispatch NOT found in kernel/reboot.c")
        ok = False

    # Show context
    for marker in ['ksu_handle_sys_reboot', '0xFAFAFAFA']:
        if marker in content:
            idx = content.index(marker)
            line_start = content.rfind('\n', 0, idx) + 1
            line_end = content.find('\n', idx)
            start_ctx = max(0, line_start - 40)
            print(f"--- context for '{marker}' ---")
            print(content[start_ctx:line_end + 100])
            print("---")

    return ok


def main():
    if len(sys.argv) > 1:
        path = sys.argv[1]
    else:
        path = find_reboot()

    if not path or not os.path.exists(path):
        print(f"ERROR: kernel/reboot.c not found at {path or '(none given)'}")
        print("Hint: run this script from the kernel source root directory")
        sys.exit(1)

    if not patch_reboot(path):
        sys.exit(1)

    if not verify_patch(path):
        print("WARNING: verification incomplete, but patch may still work")


if __name__ == "__main__":
    main()
