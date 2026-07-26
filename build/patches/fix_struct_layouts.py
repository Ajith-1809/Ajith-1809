#!/usr/bin/env python3
"""Fix struct layout mismatches in ksu_susfs_compat.c.

Extracts old code blocks by keyword boundary matching to avoid
hardcoded indentation issues.
"""

FILE = "E:/webtech/projects/btc/ff/build/patches/ksu_susfs_compat.c"


def extract_block(content, start_kw, end_kw):
    """Extract the block between start_kw and end_kw (exclusive of end_kw)."""
    idx = content.find(start_kw)
    assert idx >= 0, f'Keyword "{start_kw}" not found'
    end = content.find(end_kw, idx)
    assert end >= 0, f'End keyword "{end_kw}" not found after "{start_kw}"'
    return content[idx:end].rstrip('\n')


def main():
    with open(FILE, 'r', newline='\n') as f:
        content = f.read()
    content = content.replace('\r\n', '\n')

    # === Fix 1: SUS_PATH + SUS_PATH_LOOP ===
    old1 = extract_block(
        content,
        '/* ============ SUS_PATH commands ============ */',
        '\n\t/* ============ SUS_MOUNT commands'
    )

    new1 = (
        '\t/* ============ SUS_PATH commands ============ */\n'
        '\tcase CMD_SUSFS_ADD_SUS_PATH:\n'
        '\tcase CMD_SUSFS_ADD_SUS_PATH_LOOP: {\n'
        '\t\t/* Struct layout conversion: the binary on device was compiled\n'
        '\t\t * with master-branch struct layout (pathname at offset 0,\n'
        '\t\t * target_ino at offset 256), while the kernel-4.14 branch\n'
        '\t\t * expects target_ino at offset 0 and pathname at offset 8.\n'
        '\t\t * Read each field separately and construct the kernel struct. */\n'
        '\t\tchar bin_pathname[SUSFS_MAX_LEN_PATHNAME];\n'
        '\t\tunsigned long bin_ino;\n'
        '\t\tstruct st_susfs_sus_path _info = {0};\n'
        '\n'
        '\t\t/* Binary sends pathname at offset 0 (256 bytes) */\n'
        '\t\tif (copy_from_user(bin_pathname, arg, sizeof(bin_pathname)))\n'
        '\t\t\treturn -EFAULT;\n'
        '\t\t/* Binary sends target_ino at offset 256 */\n'
        '\t\tif (copy_from_user(&bin_ino,\n'
        '\t\t\t\t   (void __user *)arg + SUSFS_MAX_LEN_PATHNAME,\n'
        '\t\t\t\t   sizeof(bin_ino)))\n'
        '\t\t\treturn -EFAULT;\n'
        '\n'
        '\t\t/* Fill kernel-4.14 struct: target_ino at offset 0,\n'
        '\t\t * pathname at offset 8 */\n'
        '\t\t_info.target_ino = bin_ino;\n'
        '\t\tmemcpy(_info.target_pathname, bin_pathname,\n'
        '\t\t       SUSFS_MAX_LEN_PATHNAME);\n'
        '\n'
        '\t\told_fs = get_fs();\n'
        '\t\tset_fs(KERNEL_DS);\n'
        '\t\tret = susfs_add_sus_path((struct st_susfs_sus_path __user *)&_info);\n'
        '\t\tset_fs(old_fs);\n'
        '\t\tbreak;\n'
        '\t}\n'
    )

    assert old1 in content, 'Fix 1 [SUS_PATH] extracted block not in content'
    content = content.replace(old1, new1, 1)
    print('Fix 1 [SUS_PATH] applied')

    # === Fix 2: SUS_MOUNT ===
    old2 = extract_block(
        content,
        '/* ============ SUS_MOUNT commands ============ */',
        '\n\t/* ============ SUS_KSTAT commands'
    )

    new2 = (
        '\t/* ============ SUS_MOUNT commands ============ */\n'
        '\tcase CMD_SUSFS_ADD_SUS_MOUNT: {\n'
        '\t\t/* Binary sends only pathname (256 bytes) without target_dev.\n'
        '\t\t * Kernel-4.14 expects pathname + dev (264 bytes). Zero-fill\n'
        '\t\t * the dev field to avoid garbage. */\n'
        '\t\tstruct st_susfs_sus_mount _info = {0};\n'
        '\t\tif (copy_from_user(_info.target_pathname, arg,\n'
        '\t\t\t\t   sizeof(_info.target_pathname)))\n'
        '\t\t\treturn -EFAULT;\n'
        '\t\t/* target_dev stays 0 from {0} initialization */\n'
        '\t\told_fs = get_fs();\n'
        '\t\tset_fs(KERNEL_DS);\n'
        '\t\tret = susfs_add_sus_mount((struct st_susfs_sus_mount __user *)&_info);\n'
        '\t\tset_fs(old_fs);\n'
        '\t\tbreak;\n'
        '\t}\n'
    )

    assert old2 in content, 'Fix 2 [SUS_MOUNT] extracted block not in content'
    content = content.replace(old2, new2, 1)
    print('Fix 2 [SUS_MOUNT] applied')

    # === Fix 3: SUS_MAP ===
    old3 = extract_block(
        content,
        '/* ============ SUS_MAP (add_sus_map from userspace) ============ */',
        '\n\t/* ============ GKI backport commands'
    )

    new3 = (
        '\t/* ============ SUS_MAP (add_sus_map from userspace) ============ */\n'
        '\t/* Routes to susfs_add_sus_path (kernel-4.14 treats SUS_MAP as path\n'
        '\t * hiding via the SUS_PATH_HLIST). Same master-branch struct\n'
        '\t * conversion as CMD_SUSFS_ADD_SUS_PATH is needed. */\n'
        '\tcase CMD_SUSFS_ADD_SUS_MAP: {\n'
        '\t\tchar bin_pathname[SUSFS_MAX_LEN_PATHNAME];\n'
        '\t\tunsigned long bin_ino;\n'
        '\t\tstruct st_susfs_sus_path _info = {0};\n'
        '\n'
        '\t\t/* Binary sends pathname at offset 0 (256 bytes) */\n'
        '\t\tif (copy_from_user(bin_pathname, arg, sizeof(bin_pathname)))\n'
        '\t\t\treturn -EFAULT;\n'
        '\t\t/* Binary sends target_ino at offset 256 */\n'
        '\t\tif (copy_from_user(&bin_ino,\n'
        '\t\t\t\t   (void __user *)arg + SUSFS_MAX_LEN_PATHNAME,\n'
        '\t\t\t\t   sizeof(bin_ino)))\n'
        '\t\t\treturn -EFAULT;\n'
        '\n'
        '\t\t_info.target_ino = bin_ino;\n'
        '\t\tmemcpy(_info.target_pathname, bin_pathname,\n'
        '\t\t       SUSFS_MAX_LEN_PATHNAME);\n'
        '\n'
        '\t\told_fs = get_fs();\n'
        '\t\tset_fs(KERNEL_DS);\n'
        '\t\tret = susfs_add_sus_path((struct st_susfs_sus_path __user *)&_info);\n'
        '\t\tset_fs(old_fs);\n'
        '\t\tbreak;\n'
        '\t}\n'
    )

    assert old3 in content, 'Fix 3 [SUS_MAP] extracted block not in content'
    content = content.replace(old3, new3, 1)
    print('Fix 3 [SUS_MAP] applied')

    # === Fix 4: SET_UNAME ===
    old4 = extract_block(
        content,
        '/* ============ SPOOF_UNAME commands ============ */',
        '\n\t/* ============ ENABLE_LOG'
    )

    new4 = (
        '\t/* ============ SPOOF_UNAME commands ============ */\n'
        '\tcase CMD_SUSFS_SET_UNAME: {\n'
        '\t\t/* Binary was compiled with master-branch struct layout:\n'
        '\t\t *   char sysname[65]  at offset 0\n'
        '\t\t *   char nodename[65] at offset 65\n'
        '\t\t *   char release[65]  at offset 130\n'
        '\t\t *   char version[65]  at offset 195\n'
        '\t\t *   char machine[65]  at offset 260\n'
        '\t\t * Kernel-4.14 expects only:\n'
        '\t\t *   char release[65]  at offset 0\n'
        '\t\t *   char version[65]  at offset 65\n'
        '\t\t * Extract release and version from the correct offsets. */\n'
        '\t\tstruct st_susfs_uname _info = {0};\n'
        '\t\tchar bin_release[__NEW_UTS_LEN + 1];\n'
        '\n'
        '\t\t/* Binary: release at offset 130 (65 sysname + 65 nodename) */\n'
        '\t\tif (copy_from_user(bin_release,\n'
        '\t\t\t\t   (void __user *)arg + (__NEW_UTS_LEN + 1) * 2,\n'
        '\t\t\t\t   sizeof(bin_release)))\n'
        '\t\t\treturn -EFAULT;\n'
        '\t\tmemcpy(_info.release, bin_release, sizeof(bin_release));\n'
        '\n'
        '\t\t/* Binary: version at offset 195 (65*3 = sysname+nodename+release) */\n'
        '\t\tif (copy_from_user(_info.version,\n'
        '\t\t\t\t   (void __user *)arg + (__NEW_UTS_LEN + 1) * 3,\n'
        '\t\t\t\t   sizeof(_info.version)))\n'
        '\t\t\treturn -EFAULT;\n'
        '\n'
        '\t\told_fs = get_fs();\n'
        '\t\tset_fs(KERNEL_DS);\n'
        '\t\tret = susfs_set_uname((struct st_susfs_uname __user *)&_info);\n'
        '\t\tset_fs(old_fs);\n'
        '\t\tif (ret == 0) {\n'
        '\t\t\tsusfs_spoof_uname(utsname());\n'
        '\t\t\t/* Do NOT clobber live utsname()->release. The read path\n'
        '\t\t\t * (newuname) copies my_uname.release (set above) into the\n'
        '\t\t\t * returned struct, so the spoof is authoritative. Writing\n'
        '\t\t\t * the real release back here poisons utsname()->release,\n'
        '\t\t\t * which (a) makes /proc/sys/kernel/osrelease report real and\n'
        '\t\t\t * (b) gets re-captured by any later `set_uname default`\n'
        '\t\t\t * call into my_uname.release, silently killing the spoof.\n'
        '\t\t\t * The live utsname stays at the real value on purpose. */\n'
        '\t\t\tpr_info("ksu_susfs: uname spoof stored (release=\'%s\')\\n",\n'
        '\t\t\t\tutsname()->release);\n'
        '\t\t}\n'
        '\t\tbreak;\n'
        '\n'
        '\t}\n'
    )

    assert old4 in content, 'Fix 4 [SET_UNAME] extracted block not in content'
    content = content.replace(old4, new4, 1)
    print('Fix 4 [SET_UNAME] applied')

    with open(FILE, 'w', newline='\n') as f:
        f.write(content)

    print('All struct layout fixes applied successfully!')


if __name__ == '__main__':
    main()
