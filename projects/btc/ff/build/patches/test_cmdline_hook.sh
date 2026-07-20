#!/usr/bin/env bash
# test_cmdline_hook.sh - verify the build.yml awk injects the SUSFS cmdline read hook
# into phoenix's real cmdline_proc_show. Run: bash build/patches/test_cmdline_hook.sh
set -euo pipefail

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
SRC="$WORK/cmdline.c"

# phoenix v2.4 fs/proc/cmdline.c (relevant shape: show wrapped in #ifdef ALTER_CMDLINE)
cat > "$SRC" <<'PHX'
// SPDX-License-Identifier: GPL-2.0
#include <linux/fs.h>
#include <linux/init.h>
#include <linux/proc_fs.h>
#include <linux/seq_file.h>

static int cmdline_proc_show(struct seq_file *m, void *v)
{
#ifdef ALTER_CMDLINE
	seq_printf(m, "%s\n", proc_command_line);
#else
	seq_printf(m, "%s\n", saved_command_line);
#endif
	return 0;
}
PHX

# --- exact awk block from build.yml (keep in sync) ---
awk '
  /^#include <linux\/seq_file.h>/ {
    print
    print "#ifdef CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG"
    print "extern int susfs_spoof_cmdline_or_bootconfig(struct seq_file *m);"
    print "#endif"
    next
  }
  /^static int cmdline_proc_show\(struct seq_file \*m, void \*v\)/ { sig=1; print; next }
  sig && /^{/ {
    print
    print "#ifdef CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG"
    print "\tif (!susfs_spoof_cmdline_or_bootconfig(m)) {"
    print "\t\tseq_putc(m, '\''\\n'\'');"
    print "\t\treturn 0;"
    print "\t}"
    print "#endif"
    sig=0
    next
  }
  1
' "$SRC" > "$WORK/out.c"

fail=0
grep -q 'extern int susfs_spoof_cmdline_or_bootconfig' "$WORK/out.c" || { echo "FAIL: extern not injected"; fail=1; }
grep -q 'if (!susfs_spoof_cmdline_or_bootconfig(m))' "$WORK/out.c" || { echo "FAIL: read hook not injected"; fail=1; }
# hook must land INSIDE the function (after the opening brace, before original seq_printf)
hook_ln=$(grep -n 'if (!susfs_spoof' "$WORK/out.c" | cut -d: -f1)
orig_ln=$(grep -n 'saved_command_line' "$WORK/out.c" | cut -d: -f1)
[ "$hook_ln" -lt "$orig_ln" ] || { echo "FAIL: hook not before original show body"; fail=1; }
# balanced braces (injected block opens+closes its own)
ob=$(tr -cd '{' < "$WORK/out.c" | wc -c); cb=$(tr -cd '}' < "$WORK/out.c" | wc -c)
[ "$ob" -eq "$cb" ] || { echo "FAIL: unbalanced braces ob=$ob cb=$cb"; fail=1; }
# extern injected exactly once (idempotency guard relies on grep in build.yml)
n=$(grep -c 'extern int susfs_spoof_cmdline_or_bootconfig' "$WORK/out.c")
[ "$n" -eq 1 ] || { echo "FAIL: extern injected $n times (want 1)"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS: cmdline read hook injects correctly into phoenix cmdline_proc_show"
exit $fail
