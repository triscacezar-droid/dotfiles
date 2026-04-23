#!/usr/bin/env bash
# Snapshot the current kitty layout into a session file that
# `kitty --session` can replay. For any window running `claude`,
# look up the resume token in ~/.claude/sessions/<PID>.json and bake
# a `claude -r <sessionId>` into the restore command.
#
# IPC path: kitty.conf with `allow_remote_control yes` + `listen_on
# unix:@kitty` exposes full layout (OS windows × tabs × splits).
# /proc fallback: kittys started before those lines existed don't
# expose a socket. We scan /proc for `kitty` processes, walk their
# child shells, and emit one OS window per shell. Tabs/splits are
# flattened in this mode.

set -u
SOCK="unix:@kitty"
OUT="${XDG_CACHE_HOME:-$HOME/.cache}/kitty/session.conf"
mkdir -p "$(dirname "$OUT")"

json=$(kitten @ --to="$SOCK" ls 2>/dev/null || true)

KITTY_JSON="${json:-[]}" /usr/bin/env python3 - "$OUT" <<'PY'
import json, os, sys, shlex, glob

data = json.loads(os.environ.get("KITTY_JSON", "[]"))
out_path = sys.argv[1]
home = os.path.expanduser("~")
sessions_dir = os.path.join(home, ".claude", "sessions")

# ----- helpers --------------------------------------------------------------

def claude_session_id(pid):
    if not pid:
        return None
    try:
        with open(os.path.join(sessions_dir, f"{pid}.json")) as f:
            return json.load(f).get("sessionId")
    except (OSError, ValueError):
        return None

def proc_comm(pid):
    try:
        with open(f"/proc/{pid}/comm") as f:
            return f.read().strip()
    except OSError:
        return None

def proc_ppid(pid):
    try:
        with open(f"/proc/{pid}/stat") as f:
            stat = f.read()
        right = stat[stat.rfind(")") + 2:]
        return int(right.split()[1])
    except (OSError, ValueError, IndexError):
        return None

def proc_cwd(pid):
    try:
        return os.readlink(f"/proc/{pid}/cwd")
    except OSError:
        return None

def proc_cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            parts = f.read().rstrip(b"\0").split(b"\0")
        return [p.decode("utf-8", "replace") for p in parts if p]
    except OSError:
        return []

def descendants(root):
    """BFS all descendant PIDs of `root` via /proc."""
    out = []
    parents = {root}
    progressed = True
    while progressed:
        progressed = False
        for pid_dir in glob.glob("/proc/[0-9]*"):
            try:
                pid = int(os.path.basename(pid_dir))
            except ValueError:
                continue
            if pid in out or pid == root:
                continue
            ppid = proc_ppid(pid)
            if ppid in parents or ppid in out:
                out.append(pid)
                parents.add(pid)
                progressed = True
    return out

# ----- launch-cmd builder ---------------------------------------------------

def launch_cmd(cwd, fg_proc):
    if fg_proc:
        cmdline = fg_proc.get("cmdline") or []
        if cmdline and os.path.basename(cmdline[0]) == "claude":
            uuid = claude_session_id(fg_proc.get("pid"))
            if uuid:
                resume = f"claude --dangerously-skip-permissions -r {uuid}"
                return f"zsh -ic {shlex.quote(resume + '; exec zsh -i')}"
    return "zsh -i"

def fg_non_shell(window):
    for p in window.get("foreground_processes", []):
        cmdline = p.get("cmdline") or []
        if not cmdline:
            continue
        exe = os.path.basename(cmdline[0])
        if exe in ("zsh", "bash", "sh", "fish", "dash"):
            continue
        return p
    return None

# ----- IPC path -------------------------------------------------------------

lines = []
ipc_fg_pids = set()  # track shell pids we've covered via IPC

for os_idx, os_win in enumerate(data):
    if os_idx > 0:
        lines.append("new_os_window")
    tabs = os_win.get("tabs", [])
    for tab_idx, tab in enumerate(tabs):
        title = tab.get("title") or ""
        if tab_idx > 0:
            lines.append(f"new_tab {title}" if title else "new_tab")
        elif title:
            lines.append(f"tab_title {title}")
        layout = tab.get("layout") or "tall"
        lines.append(f"layout {layout}")
        for w in tab.get("windows", []):
            cwd = w.get("cwd") or home
            # Track shell pid so /proc fallback skips this window.
            for p in w.get("foreground_processes", []):
                pid = p.get("pid")
                if pid:
                    ipc_fg_pids.add(pid)
            cmd = launch_cmd(cwd, fg_non_shell(w))
            lines.append(f"launch --cwd={cwd} {cmd}")

# ----- /proc fallback for pre-socket kittys --------------------------------

kitty_pids = [
    int(os.path.basename(d)) for d in glob.glob("/proc/[0-9]*")
    if proc_comm(int(os.path.basename(d))) == "kitty"
]

for k_pid in kitty_pids:
    desc = descendants(k_pid)
    # For each direct shell child, emit one OS window.
    for pid in desc:
        cmdline = proc_cmdline(pid)
        if not cmdline:
            continue
        exe = os.path.basename(cmdline[0])
        if exe not in ("zsh", "bash", "sh", "fish", "dash"):
            continue
        # Skip if this shell is already visible via IPC.
        if pid in ipc_fg_pids:
            continue
        # Also skip if any of its descendant PIDs are IPC-visible (covers
        # the case where the foreground is `claude` but its parent zsh is
        # what /proc would enumerate).
        sub = descendants(pid)
        if any(sp in ipc_fg_pids for sp in sub):
            continue
        cwd = proc_cwd(pid) or home
        # Is a claude process the direct child?
        fg_proc = None
        for sp in sub:
            sp_cmdline = proc_cmdline(sp)
            if sp_cmdline and os.path.basename(sp_cmdline[0]) == "claude":
                fg_proc = {"pid": sp, "cmdline": sp_cmdline}
                break
        if lines:
            lines.append("new_os_window")
        lines.append(f"launch --cwd={cwd} {launch_cmd(cwd, fg_proc)}")

# ----- write ---------------------------------------------------------------

if lines:
    with open(out_path, "w") as f:
        f.write("\n".join(lines) + "\n")
PY
