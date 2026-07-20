#!/usr/bin/env python3
"""
patch_allowlist.py — Move ksu_grant_root_to_shell() before DISABLE_POLICY check

CONFIG_KSU_DISABLE_POLICY=y makes ksu_load_allow_list() return early at the
#ifdef guard, BEFORE ksu_grant_root_to_shell() can register UID 2000 (ADB
shell) in the allowlist. This fix moves the grant_root_to_shell call above
the DISABLE_POLICY guard so shell always gets root access.

Strategy: Rewrite the function to:
  1. Declare variables first
  2. Call ksu_grant_root_to_shell() (if CONFIG_KSU_DEBUG)
  3. If CONFIG_KSU_DISABLE_POLICY, return early (skip file loading)
  4. Otherwise, load the allowlist file as before
"""

import sys

ALLOWLIST_C_PATH = "KernelSU-Next/kernel/policy/allowlist.c"


def find_block(content, anchor_start, anchor_end=None):
    """Find a block by start anchor; if anchor_end given, find its extent."""
    start = content.find(anchor_start)
    if start < 0:
        return (-1, -1)
    if anchor_end:
        end = content.find(anchor_end, start + len(anchor_start))
        if end < 0:
            return (start, -1)
        return (start, end + len(anchor_end))
    return (start, start + len(anchor_start))


def patch_allowlist_c(path=ALLOWLIST_C_PATH):
    with open(path, "r") as f:
        content = f.read()

    # ── Locate ksu_load_allow_list() ────────────────────────────────────
    FUNC = "void ksu_load_allow_list()\n"
    func_start_sig = FUNC + "{\n"
    idx = content.find(func_start_sig)
    if idx < 0:
        # Try signature without space before parens
        idx = content.find(FUNC)
        if idx < 0:
            print(f"ERROR: could not find ksu_load_allow_list() in {path}")
            sys.exit(1)
        # Find the opening brace on the next line
        brace = content.find("\n{", idx)
        if brace < 0:
            print("ERROR: could not find opening brace of ksu_load_allow_list()")
            sys.exit(1)
        func_start_sig = content[idx:brace+2]
        idx = content.find(func_start_sig)

    func_body_start = idx + len(func_start_sig)
    func_body = content[func_body_start:]

    # ── Check if already patched (within function body) ─────────────────
    need_dup_check = True

    # DEBUG block (ksu_grant_root_to_shell) within function
    dbg_anchor = "#ifdef CONFIG_KSU_DEBUG\n\t// always allow adb shell by default\n\tksu_grant_root_to_shell();\n#endif\n"
    dbg_idx = func_body.find(dbg_anchor)

    # DISABLE_POLICY block within function
    dis_anchor = ("#ifdef CONFIG_KSU_DISABLE_POLICY\n"
                  "\tpr_info(\"allowlist load skipped because policy is disabled\\n\");\n"
                  "\treturn;\n"
                  "#endif\n")
    dis_idx = func_body.find(dis_anchor)

    if dbg_idx >= 0 and dis_idx >= 0 and dbg_idx < dis_idx:
        print("  already patched: ksu_grant_root_to_shell() before DISABLE_POLICY within function")
        return True

    if dis_idx < 0:
        print("ERROR: could not find CONFIG_KSU_DISABLE_POLICY block in function body")
        print("Looking for:")
        print(repr(dis_anchor))
        print("Function body excerpt:")
        print(func_body[:500])
        sys.exit(1)

    # ── Find all segments within the function body ──────────────────────
    # Segment 1: prefix between `{` and the DISABLE_POLICY block
    prefix = func_body[:dis_idx]

    # Segment 2: the DISABLE_POLICY block itself
    disable_block = func_body[dis_idx:dis_idx + len(dis_anchor)]

    # Segment 3: between DISABLE_POLICY block and var decls
    var_start = "\tloff_t off = 0;\n"
    var_end_clause = "    size_t app_profile_size;\n"
    var_start_idx = func_body.find(var_start, dis_idx + len(dis_anchor))
    if var_start_idx < 0:
        print("ERROR: could not find variable declaration block")
        sys.exit(1)

    after_disable = dis_idx + len(dis_anchor)
    middle = func_body[after_disable:var_start_idx]

    var_bottom = var_start_idx + len(var_start)
    # Find the end of the variable declarations (the app_profile_size line)
    # Need to account for possible blank line after it
    var_end_idx = func_body.find(var_end_clause, var_bottom)
    if var_end_idx < 0:
        print("ERROR: could not find '    size_t app_profile_size;'")
        sys.exit(1)
    var_block = func_body[var_start_idx:var_end_idx + len(var_end_clause)]
    var_rest_start = var_end_idx + len(var_end_clause)

    # Segment 4: the DEBUG block (ksu_grant_root_to_shell)
    dbg_start_idx = func_body.find(dbg_anchor, var_rest_start)
    if dbg_start_idx < 0:
        # Maybe there's no DEBUG block (CONFIG_KSU_DEBUG not set in source)
        # In that case we still need to move DISABLE_POLICY after var decls
        # But without ksu_grant_root_to_shell, this is less useful
        print("WARNING: DEBUG block not found — ksu_grant_root_to_shell() may not be compiled")
        # Restructure: prefix -> var_block -> disable_block -> rest
        new_body = prefix + var_block + disable_block + func_body[var_rest_start:]
        changed = True
        print("  moved: DISABLE_POLICY guard after variable declarations")
    else:
        debug_block = func_body[dbg_start_idx:dbg_start_idx + len(dbg_anchor)]
        rest = func_body[dbg_start_idx + len(dbg_anchor):]

        # Reassembled: prefix + var_block + debug_block + disable_block + rest
        new_body = prefix + var_block + debug_block + "\n" + disable_block + rest
        changed = True
        print("  reconstructed: vars -> ksu_grant_root_to_shell() -> DISABLE_POLICY guard")

    if not changed:
        print("  nothing to change")
        return True

    # ── Write ───────────────────────────────────────────────────────────
    new_content = content[:func_body_start] + new_body
    with open(path, "w") as f:
        f.write(new_content)
    print("  allowlist.c written")

    # ── Verify ──────────────────────────────────────────────────────────
    final_body = new_content[func_body_start:]
    dbg_final = final_body.find(dbg_anchor)
    dis_final = final_body.find(dis_anchor)
    if dbg_final >= 0 and dis_final >= 0:
        if dbg_final < dis_final:
            print("  VERIFIED: correct ordering within function body")
        else:
            print("  WARNING: debug block still after disable policy block")
            print(f"    debug at {dbg_final}, disable at {dis_final}")

    return True


if __name__ == "__main__":
    path = sys.argv[1] if len(sys.argv) > 1 else ALLOWLIST_C_PATH
    patch_allowlist_c(path)
