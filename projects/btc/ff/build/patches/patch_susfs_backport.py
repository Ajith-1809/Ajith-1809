#!/usr/bin/env python3
"""
patch_susfs_backport.py — Wire the SUSFS GKI backport (SUS_MAP / SUS_MEMFD /
SUS_PROC_FD_LINK) into the kernel tree so those config features become functional
on kernel 4.14 (CAF/phoenix).

Why this exists:
  The build compiles the *stock* GitLab susfs.c (kernel-4.14 branch) which has no
  SUS_MAP/MEMFD/PROC_FD_LINK code. A fuller backport lives in
  build/patches/susfs_v2/susfs_gki_backport.c whose header says it is "Appended to
  the base 4.14 susfs.c during CI build." That backport:
    - implements susfs_add_sus_maps / susfs_update_sus_maps /
      susfs_add_sus_proc_fd_link / susfs_add_sus_memfd (all EXPORT_SYMBOL) and the
      display spoofer susfs_sus_maps();
    - but its call sites are ORPHANED: nothing in the tree calls susfs_sus_maps(),
      and the supercall dispatch stubs the four CMDs to -EOPNOTSUPP.

This script (run in CI after fs/susfs.c and fs/proc/task_mmu.c exist):
  (a) appends the backport to fs/susfs.c (same translation unit => shares
      susfs_spin_lock, SUSFS_LOGI/LOGE, SUSFS_MAX_LEN_PATHNAME);
  (b) redirects task_mmu.c show_map_vma to consult susfs_sus_maps() so /proc/pid/maps
      entries are actually spoofed.

The dispatch-side wiring (replacing the -EOPNOTSUPP stubs in ksu_susfs_compat.c) is a
separate tracked-file edit, not done here.

Conventions: 4-space indent, docstrings, set -euo pipefail at the CI call site.
"""
import os
import sys

# Anchors must be unique in the target files.
TASK_MMU = "fs/proc/task_mmu.c"
SUSFS_C = "fs/susfs.c"
BACKPORT_SRC_REL = "build/patches/susfs_v2/susfs_gki_backport.c"  # relative to workspace

PATCH_MARKER = "/* SUSFS GKI backport appended */"

EXTERN_ANCHOR = (
    "extern void susfs_sus_ino_for_show_map_vma(unsigned long ino, "
    "dev_t *out_dev, unsigned long *out_ino);"
)
EXTERN_INSERT = (
    "#ifdef CONFIG_KSU_SUSFS_SUS_MAP\n"
    "extern int susfs_sus_maps(unsigned long ino, unsigned long addr_size,\n"
    "                          unsigned long *spoofed_ino, dev_t *spoofed_dev,\n"
    "                          int *spoofed_flags, unsigned long long *spoofed_pgoff,\n"
    "                          struct vm_area_struct *vma, char *out_name);\n"
    "#endif\n"
)

# Function-local SUS_MAP scratch vars, declared alongside the other locals
# (right after `const char *name = NULL;`). `susfs_map_name` is the buffer the
# spoofer fills with the replacement pathname on a full spoof (ret == 2).
LOCAL_ANCHOR = "\tconst char *name = NULL;"
LOCAL_INSERT = (
    "#ifdef CONFIG_KSU_SUSFS_SUS_MAP\n"
    "\tint susfs_map_ret = 0;\n"
    "\tunsigned long long susfs_map_pgoff = 0;\n"
    "\tint susfs_map_flags = 0;\n"
    "\tchar susfs_map_name[256] = {0};\n"
    "#endif\n"
)

# Invoke the spoofer right AFTER dev/ino/pgoff are resolved from the file
# (before `start = vma->vm_start;`). The spoofer rewrites *spoofed_ino /
# *spoofed_dev / *spoofed_pgoff (used by the header) and, on a full spoof,
# fills susfs_map_name (used by the path print below).
CALL_ANCHOR = "\tstart = vma->vm_start;"
CALL_INSERT = (
    "#ifdef CONFIG_KSU_SUSFS_SUS_MAP\n"
    "\tif (file) {\n"
    "\t\tsusfs_map_ret = susfs_sus_maps(ino, vma->vm_end - vma->vm_start,\n"
    "\t\t\t\t\t   &ino, &dev, &susfs_map_flags,\n"
    "\t\t\t\t\t   &susfs_map_pgoff, vma, susfs_map_name);\n"
    "\t\tif (susfs_map_ret >= 1 && susfs_map_pgoff)\n"
    "\t\t\tpgoff = susfs_map_pgoff;\n"
    "\t}\n"
    "#endif\n"
)

# The path string is printed by seq_file_path() inside the SECOND `if (file)`
# block — which runs AFTER show_vma_header_prefix(). Replace it with the
# spoofed pathname when the spoofer returned a full spoof (ret == 2).
PATH_ANCHOR = "\t\tseq_file_path(m, file, \"\\n\");"
PATH_INSERT = (
    "#ifdef CONFIG_KSU_SUSFS_SUS_MAP\n"
    "\t\tif (susfs_map_ret == 2 && susfs_map_name[0])\n"
    "\t\t\tseq_printf(m, \"%s\\n\", susfs_map_name);\n"
    "\t\telse\n"
    "#endif\n"
    "\t\t\tseq_file_path(m, file, \"\\n\");"
)


def read_text(path):
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        return f.read()


def write_text(path, text):
    with open(path, "w", encoding="utf-8", errors="replace") as f:
        f.write(text)


def append_backport(susfs_c_path, backport_path):
    if PATCH_MARKER in read_text(susfs_c_path):
        print("  fs/susfs.c: backport already appended — skipping")
        return
    backport = read_text(backport_path)
    # Drop the backport's own SUSFS_MAX_LEN_PATHNAME #define lines: stock susfs.c
    # already gets the same macro (256) from linux/susfs_def.h via linux/susfs.h.
    # Re-#defining (even with the same value) is fragile under -Werror, so strip it.
    lines = []
    for ln in backport.splitlines():
        if ln.strip().startswith("#define SUSFS_MAX_LEN_PATHNAME"):
            continue
        lines.append(ln)
    backport = "\n".join(lines)

    original = read_text(susfs_c_path)
    combined = original.rstrip() + "\n\n" + PATCH_MARKER + "\n" + backport.rstrip() + "\n"
    write_text(susfs_c_path, combined)
    print("  fs/susfs.c: GKI backport appended")


def wire_task_mmu(task_mmu_path):
    text = read_text(task_mmu_path)
    if "susfs_sus_maps(" in text:
        print("  fs/proc/task_mmu.c: SUS_MAP already wired — skipping")
        return

    if EXTERN_ANCHOR not in text:
        raise SystemExit(
            "::error::task_mmu.c missing anchor ext: %r" % EXTERN_ANCHOR)
    if LOCAL_ANCHOR not in text:
        raise SystemExit(
            "::error::task_mmu.c missing anchor local: %r" % LOCAL_ANCHOR)
    if CALL_ANCHOR not in text:
        raise SystemExit(
            "::error::task_mmu.c missing anchor call: %r" % CALL_ANCHOR)
    if PATH_ANCHOR not in text:
        raise SystemExit(
            "::error::task_mmu.c missing anchor path: %r" % PATH_ANCHOR)

    # 1) extern declaration right after the existing SUS_KSTAT extern.
    text = text.replace(EXTERN_ANCHOR, EXTERN_ANCHOR + "\n" + EXTERN_INSERT, 1)
    # 2) function-local scratch vars right after `const char *name = NULL;`.
    text = text.replace(LOCAL_ANCHOR, LOCAL_ANCHOR + "\n" + LOCAL_INSERT, 1)
    # 3) spoofer call right after dev/ino/pgoff are resolved.
    text = text.replace(CALL_ANCHOR, CALL_INSERT + CALL_ANCHOR, 1)
    # 4) override the path print when a full spoof (ret == 2) is active.
    text = text.replace(PATH_ANCHOR, PATH_INSERT, 1)
    write_text(task_mmu_path, text)
    print("  fs/proc/task_mmu.c: SUS_MAP wired into show_map_vma")


def main():
    workspace = os.environ.get("GITHUB_WORKSPACE", ".")
    project_root = os.environ.get("PROJECT_ROOT", ".")
    here = os.getcwd()

    susfs_c_path = os.path.join(here, SUSFS_C)
    task_mmu_path = os.path.join(here, TASK_MMU)
    backport_path = os.path.join(workspace, project_root, BACKPORT_SRC_REL)

    for p in (susfs_c_path, task_mmu_path, backport_path):
        if not os.path.isfile(p):
            raise SystemExit("::error::missing required file: %s" % p)

    # Safety: the stock susfs.c must provide the symbols the backport relies on.
    susfs_c = read_text(susfs_c_path)
    for sym in ("susfs_spin_lock", "SUSFS_LOGI", "SUSFS_LOGE"):
        if sym not in susfs_c:
            raise SystemExit(
                "::error::fs/susfs.c missing expected symbol %r "
                "(backport depends on it)" % sym)

    append_backport(susfs_c_path, backport_path)
    wire_task_mmu(task_mmu_path)

    # Final verification (CI also greps, but fail fast here too).
    final = read_text(susfs_c_path)
    if "susfs_sus_maps" not in final:
        raise SystemExit("::error::backport append did not land susfs_sus_maps")
    if "susfs_sus_maps(" not in read_text(task_mmu_path):
        raise SystemExit("::error::task_mmu.c SUS_MAP call not wired")
    print("=== SUSFS GKI backport integration OK ===")


if __name__ == "__main__":
    main()
