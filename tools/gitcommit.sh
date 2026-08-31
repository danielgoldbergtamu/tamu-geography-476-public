#!/usr/bin/env bash
# Commit a project through the Cowork device bridge, which cannot delete files.
#
# WHY THIS EXISTS. Git writes lock files - .git/index.lock, HEAD.lock,
# objects/maintenance.lock - and deletes them when it finishes. THE BRIDGE CANNOT DELETE.
# So every git write leaves its locks behind, and the NEXT git write fails with
# "Unable to create '.git/index.lock': File exists." The operation that failed is not the
# one that broke anything; the one before it was.
#
# The second failure mode is identity. A fresh repo has no user.name or user.email and
# `git commit` aborts with "Author identity unknown" before touching anything.
#
# BOTH ARE FIXED HERE. Locks are MOVED to the repo's own _to_delete/ (root CLAUDE.md section 2:
# moving is the only deletion available, and section 9: lock files are moved, never deleted),
# before AND after each write. Identity is read from the repo's own config, which
# init_project.py sets at creation from 00_System/git_identity.conf.
#
# WHAT THIS DOES NOT DO: push. Root CLAUDE.md section 6 - `git push` is Dan's, always.
# The script prints the one-line PowerShell for him to paste.
#
# USAGE
#   --sweep               move aside the git lock files and exit, without committing
#   --push-line           print the paste-ready PowerShell push line and exit (rule 24)
#   --nothing-found WHY   record that this session found nothing (rule 22)
#   tools/gitcommit.sh -m "Subject line" [-b body-file]
#   tools/gitcommit.sh -f message-file
#   echo "msg" | tools/gitcommit.sh -
#
#   tools/gitcommit.sh -m "Subject" -- path/one path/two
#       Stage and commit ONLY the named paths. Reported by AI_Tooling, 30 August 2026: the
#       header documented -m, -f, -b and - and nothing else, while the script had grown
#       positional PATHS, a `--` separator and --include-untracked. A flag that exists and is
#       undocumented is a flag nobody uses -- in USGIF this one's absence swept 41 files of an
#       earlier session's unfinished work into a commit.
#
#   --include-untracked   allow the no-paths form to stage untracked files too. WITHOUT a
#                         path list the script REFUSES when untracked files are present,
#                         because `git add -A` is what caused that USGIF commit.
#
set -uo pipefail

# ONE source for the push line. Synced rule 13: a string that appears in two places has one
# source. It appeared here twice - once for --push-line and once after a successful commit - in
# two different forms, and Dan noticed the difference between two projects in one session.
# The abbreviated -EA is deliberate: the spelled-out form wraps in the chat and is harder to paste.
push_line() {
    printf "cd '%s'; Get-ChildItem .git -Recurse -Force -Filter '*.lock' -EA SilentlyContinue | Remove-Item -Force -EA SilentlyContinue; git push -u origin %s\n" "$1" "$2"
}

# THE WINDOWS PATH, RESOLVED ONCE. push_line() was unified on 31 August 2026 but the PATH it
# is given was not, and the two callers disagreed: the commit path used foreman_paths.py with
# a /mnt/Claude -> C:\Claude sed fallback, while --push-line imported foreman_paths from
# $REPO/tools and, failing that, printed the raw sandbox path. So `--push-line` in a repo
# without tools/ emitted
#     cd '/sessions/rcw-.../mnt/Claude/00_System'; git push ...
# which is not a thing Dan can paste into PowerShell. A push line that cannot be pasted is
# worse than none: it looks like the deliverable and is not.
#
# Found extending gitcommit.sh to the non-project repositories (Sanborn report) -- 00_System
# and 476-public are git repositories with no tools/, which is exactly the case both callers
# handled differently and neither handled well.
win_path() {
    _p="$1" _out=""
    if [ -f "$HELPER_PY" ] && command -v python3 >/dev/null 2>&1; then
        _out="$(python3 "$HELPER_PY" --winpath "$_p" 2>/dev/null || true)"
    fi
    if [ -z "$_out" ]; then
        case "$(basename "$_p")" in
            [A-Za-z]:--*)  _out="$(basename "$_p" | sed 's|--|\\|g')" ;;
            *)             _out="$(echo "$_p" | sed 's|.*/mnt/Claude|C:\\Claude|; s|/|\\|g')" ;;
        esac
    fi
    printf "%s\n" "$_out"
}

REPO="$(git rev-parse --show-toplevel 2>/dev/null || echo .)"
cd "$REPO" || { echo "FAIL  not inside a git repository"; exit 1; }

# foreman_paths.py may sit beside this script (a project's tools/) or nowhere at all (a
# non-project repository that has only gitcommit.sh). Both are fine; win_path degrades.
HELPER_PY="$(dirname "$0")/foreman_paths.py"
[ -f "$HELPER_PY" ] || HELPER_PY="$REPO/tools/foreman_paths.py"

# FINDING THE WORKSPACE ROOT. The folder holding Foreman (or 00_System). It is used for ONE
# thing now -- locating git_identity.conf -- and not finding it is not fatal.
#
# AMENDED 30 August 2026, twice, and the old text is kept here because it explains the shape
# of the code. It used to read: "the folder holding both CLAUDE.md and 00_System, because that
# is where _to_delete/ lives - root section 2 says there is exactly one, at the workspace root,
# and never a project-level one." BOTH halves of that are now false. Root section 2 was reversed
# on Dan's correction: _to_delete is PER PROJECT, so locks sweep to the repo's own. And
# requiring CLAUDE.md made the probe unsatisfiable on the device bridge, where the root
# constitution is outside every project mount by construction.
#
# AMENDED 30 August 2026 from an onboarding-friction report by the ADH project (kind
# UNDOCUMENTED): the walk fails when the project folder IS the mount root, or when a session
# runs the script from a mount that does not contain 00_System. It then fell back to the
# repo's parent, found no git_identity.conf there, and would have exited with no identity AND
# silently swept nothing - because mkdir was `2>/dev/null` and its failure was discarded.
# That was caught only because someone noticed first. Two fixes: an explicit override, and
# a sweep that refuses to pretend.
if [ -n "${CLAUDE_WS_ROOT:-}" ]; then
    WS_ROOT="$CLAUDE_WS_ROOT"
    { [ -d "$WS_ROOT/Foreman" ] || [ -d "$WS_ROOT/00_System" ]; } || \
        echo "  warning: CLAUDE_WS_ROOT=$WS_ROOT holds neither Foreman nor 00_System"
else
    # Probe for Foreman or 00_System ONLY. It used to also require CLAUDE.md, and
    # on the device bridge that can never succeed: the root constitution lives at
    # the workspace root, which is not inside any connected project folder. Reported
    # by UGC 30 August 2026. Its old remedy line advised setting CLAUDE_WS_ROOT --
    # the exact habit that mangled a project name into the filename
    # C:--Claude--USGIF.md -- so that advice is gone too.
    WS_ROOT="$(cd "$REPO" && while [ "$PWD" != "/" ]; do { [ -d "$PWD/Foreman" ] || [ -d "$PWD/00_System" ]; } && { echo "$PWD"; break; }; cd ..; done)"
fi
if [ -z "$WS_ROOT" ]; then
    # NOT fatal. WS_ROOT is only used to find git_identity.conf, and git has its own
    # identity fallbacks. Refusing to commit because the workspace is not connected
    # would block the one thing a project session must always be able to do.
    echo "  note: workspace root not reachable; using git's own identity settings."
fi
# Per project, not the workspace. Root CLAUDE.md section 2 was AMENDED 30 August 2026:
# "_to_delete is per project". Sweeping one repo's locks into a shared folder put
# twelve projects' discards in one pile and made this repo non-portable.
LOCKDIR="$REPO/_to_delete/$(date +%Y-%m-%d)_git_locks"

# Prove the lock directory before doing anything. A sweep that cannot move a lock is not a
# sweep, and the git command after it fails for a reason that has nothing to do with git.
if ! mkdir -p "$LOCKDIR" 2>/dev/null; then
    echo "FAIL  cannot create the lock directory: $LOCKDIR"
    echo "      Locks are MOVED, never deleted - the bridge cannot unlink. Without this"
    echo "      directory every git write here will poison the next one."
    echo "      Fix the path, or set CLAUDE_WS_ROOT to the folder holding 00_System."
    exit 1
fi

sweep() {
    # Move every lock and abandoned temp object out of the way. Never rm - it fails.
    local n=0 f
    mkdir -p "$LOCKDIR" 2>/dev/null
    for f in $(find .git \( -name '*.lock' -o -name 'tmp_obj_*' \) 2>/dev/null); do
        mv "$f" "$LOCKDIR/$(basename "$REPO")_$(echo "$f" | tr '/' '_').$$.$RANDOM" 2>/dev/null && n=$((n+1))
    done
    [ "$n" -gt 0 ] && echo "  swept $n stale lock/temp file(s) -> _to_delete/"
    return 0
}

# Run a git command with the lock dance around it. Retries once after a sweep, because
# git's own background maintenance can recreate a lock between the sweep and the command.
# Returns git's exit status. NEVER swallows a failure.
git_try() {
    local attempt out rc
    for attempt in 1 2 3; do
        sweep
        out="$(git "$@" 2>&1)"; rc=$?
        printf '%s\n' "$out" | grep -v '^warning: unable to unlink' | grep -v '^$' | sed 's/^/  /'
        sweep
        [ $rc -eq 0 ] && return 0
        printf '%s' "$out" | grep -q "index.lock\|File exists\|Another git process" || return $rc
        echo "  lock contention - retrying ($attempt)"
        sleep 1
    done
    return 1
}

MSG=""
PATHS=()
INCLUDE_UNTRACKED=0
NOTHING_FOUND=""
PUSH_LINE_ONLY=0
SWEEP_ONLY=0
while [ $# -gt 0 ]; do
    case "$1" in
        -m) MSG="$2"; shift 2;;
        -f) MSG="$(cat "$2")"; shift 2;;
        -b) MSG="$MSG

$(cat "$2")"; shift 2;;
        -)  MSG="$(cat)"; shift;;
        --include-untracked) INCLUDE_UNTRACKED=1; shift;;
        --nothing-found) NOTHING_FOUND="$2"; shift 2;;
        --push-line) PUSH_LINE_ONLY=1; shift;;
        --sweep) SWEEP_ONLY=1; shift;;
        --) shift; while [ $# -gt 0 ]; do PATHS+=("$1"); shift; done;;
        -*) echo "FAIL  unknown option: $1"; exit 2;;
        *)  PATHS+=("$1"); shift;;
    esac
done
# --- PRINT THE PASTE-READY LINE AND STOP ------------------------------------
# Synced rule 24. Reported by 215, 30 August 2026: "Dan was told twice in this session that a
# commit was ready with no way to act on it." This script has always printed the push line
# AFTER a successful commit -- but a session that commits with raw `git commit` (to work
# around the lock files the bridge cannot delete, which is common) never reaches that code,
# and the line is silently skipped. That is exactly what happened on 31 August: five repos
# were committed and reported with no push line offered.
#
# So the line is available WITHOUT committing. There is now no reason not to show it.
if [ "$PUSH_LINE_ONLY" = "1" ]; then
    _B="$(git --no-optional-locks symbolic-ref --short HEAD 2>/dev/null || echo main)"
    push_line "$(win_path "$REPO")" "$_B"
    exit 0
fi

# --- SWEEP THE LOCKS AND STOP ------------------------------------------------
# Reported by Sanborn, 30 August 2026: "There is still no way to sweep git lock files without
# committing." The sweep only ever ran as part of a commit, so a repository jammed by a lock
# could not be UNjammed without making a commit -- and the commit is the thing the lock is
# stopping. Circular, and it bit this session repeatedly: every failed git command left a lock
# that blocked the next one, because the bridge cannot delete.
#
# The locks are MOVED, not deleted, for the same reason: rule 12, and the bridge forbids unlink.
if [ "$SWEEP_ONLY" = "1" ]; then
    sweep
    echo "  remaining: $(find "$REPO/.git" -name '*.lock' 2>/dev/null | wc -l) lock(s)"
    exit 0
fi

[ -z "$MSG" ] && { echo "FAIL  no commit message. Use -m, -f, or pipe with -"; exit 2; }

NAME="$(git config user.name || true)"
EMAIL="$(git config user.email || true)"
if [ -z "$NAME" ] || [ -z "$EMAIL" ]; then
    CONF="${WS_ROOT:-/nonexistent}/00_System/git_identity.conf"
    if [ -f "$CONF" ]; then
        NAME="$(grep -m1 '^name=' "$CONF" | cut -d= -f2-)"
        EMAIL="$(grep -m1 '^email=' "$CONF" | cut -d= -f2-)"
        git config user.name  "$NAME"
        git config user.email "$EMAIL"
        echo "  identity set from 00_System/git_identity.conf"
    else
        echo "FAIL  no git identity, and no $CONF to read one from."
        exit 1
    fi
fi

# Every commit ends with the co-author line. Root CLAUDE.md section 9.
COAUTHOR="Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
case "$MSG" in *"$COAUTHOR"*) ;; *) MSG="$MSG

$COAUTHOR";; esac

echo "== $(basename "$REPO")"

# Git's background maintenance recreates locks behind us. Turn it off, once, per repo.
[ "$(git config gc.auto)" = "0" ] || git config gc.auto 0
[ "$(git config maintenance.auto)" = "false" ] || git config maintenance.auto false

BEFORE="$(git rev-parse HEAD 2>/dev/null || echo none)"

# NEVER `git add -A`. Reported by UGC 30 August 2026: with concurrent sessions in
# the same repo, -A swept 16 files into one commit -- three other sessions' untracked
# tools, another session's in-flight edit, a superseded builder, and six binary git
# temp objects this script had itself just swept aside. The same defect took 148 files
# earlier the same day. The damage is invisible at the time and shows up later as a
# commit whose message describes one change and whose diff contains five.
if [ ${#PATHS[@]} -gt 0 ]; then
    git_try add -- "${PATHS[@]}" || { echo "  FAIL  could not stage the named paths"; exit 1; }
else
    UNTRACKED="$(git --no-optional-locks -C "$REPO" ls-files --others --exclude-standard)"
    if [ -n "$UNTRACKED" ] && [ "$INCLUDE_UNTRACKED" != "1" ]; then
        echo "  FAIL  untracked files present and no paths were named."
        echo "        Staging them blindly is how another session's work ends up in"
        echo "        your commit. Name what you mean, or pass --include-untracked:"
        echo "$UNTRACKED" | sed 's/^/          /' | head -20
        n=$(echo "$UNTRACKED" | wc -l); [ "$n" -gt 20 ] && echo "          ... and $((n-20)) more"
        exit 1
    fi
    if [ "$INCLUDE_UNTRACKED" = "1" ]; then
        git_try add -A || { echo "  FAIL  could not stage"; exit 1; }
    else
        git_try add -u || { echo "  FAIL  could not stage"; exit 1; }
    fi
fi

if [ -z "$(git status --porcelain 2>/dev/null)" ]; then
    echo "  nothing to commit"
    exit 0
fi

# --- THE RECORDING GATE -----------------------------------------------------
# Synced rule 22. Dan, 31 August 2026: "no project ever does not record things as it goes.
# Always record everything that I need to remember to come back to."
#
# WHY HERE. This is the one moment a session knows what it found AND is still running. Rule 3
# asks for a friction report before the first action; nothing asked at the end, and 215 lost
# fourteen findings to that gap in a single day.
#
# WHY IT CANNOT BE ANSWERED WITH SILENCE. A session that found nothing and one that found
# things and wrote none of them down are indistinguishable from outside. So the gate takes
# either a ledger entry or an EXPLICIT claim of nothing, and the claim is written into the
# ledger where a run of them is visible. Refusing to be answered is what makes it a gate;
# refusing to be answered HONESTLY is what would make it useless.
#
# Hard by Dan's choice, 31 August 2026: "let's start with a hard gate and see what it actually
# interrupts. if it is too cumbersome, we can relax to a warning."
FINDINGS_TOOL=""
for c in "$REPO/tools/findings.py" "${WS_ROOT:-/nonexistent}/Foreman/01_Template/scripts/findings.py"; do
    [ -f "$c" ] && { FINDINGS_TOOL="$c"; break; }
done
if [ -n "$FINDINGS_TOOL" ] && [ -f "$REPO/CLAUDE.md" ]; then
    if [ -n "$NOTHING_FOUND" ]; then
        python3 "$FINDINGS_TOOL" --root "$REPO" --nothing-found "$NOTHING_FOUND" || {
            echo "  FAIL  could not record the nothing-found claim"; exit 1; }
        git_try add -- "$(cd "$REPO" && python3 -c "
import sys; sys.path.insert(0,'$(dirname "$FINDINGS_TOOL")')
import findings, os
print(os.path.relpath(findings.ledger_path('$REPO'), '$REPO'))" 2>/dev/null)" || true
    elif ! python3 "$FINDINGS_TOOL" --root "$REPO" --recorded-since HEAD >/dev/null 2>&1; then
        echo "  FAIL  nothing was recorded, and this commit changes the project."
        echo
        echo "        Rule 22: a session records what it found, or says it found nothing."
        echo "        Neither the findings ledger, the register nor the decision log is in"
        echo "        this commit."
        echo
        echo "        Record a finding:"
        echo "          python3 tools/findings.py --claim \"what you saw\" --bites SOURCE"
        echo "        Or state that there was nothing, which is also recorded:"
        echo "          tools/gitcommit.sh -m \"...\" --nothing-found \"why\""
        exit 1
    fi
fi

TMPMSG="$(mktemp)"; printf '%s\n' "$MSG" > "$TMPMSG"
git_try commit -q -F "$TMPMSG"
rm -f "$TMPMSG" 2>/dev/null

# THE SUCCESS TEST IS THAT HEAD MOVED. A previous commit existing is not success -
# an earlier version of this script printed the OLD commit and called it done.
AFTER="$(git rev-parse HEAD 2>/dev/null || echo none)"
if [ "$AFTER" = "$BEFORE" ] || [ "$AFTER" = "none" ]; then
    echo "  FAIL  no new commit - HEAD did not move"
    echo "        $(git status --porcelain 2>/dev/null | wc -l) file(s) still uncommitted"
    exit 1
fi
echo "  committed: $(git log --oneline -1)"

BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null || echo master)"
# THE WINDOWS PATH, and there are two mount shapes to decode.
#
# When the workspace root is the connected folder, the repo is at .../mnt/Claude/<project> and the
# prefix rewrite is enough. But Cowork mounts EVERY connected folder as a SIBLING under mnt/, so a
# session that connected one project directly gets .../mnt/C:--Claude--<Project> - the Windows path
# encoded in the folder name, with `--` standing in for the separator. The old rewrite did not match
# that shape, fell through to the generic slash swap, and printed a LINUX path with backslashes:
#   cd '\sessions\rcw-...\mnt\C:--Claude--USGIF'; git push
# which is not a path on the user's machine and fails the moment it is pasted. Found 2026-08-30 in
# USGIF. Same root cause as the foreman_sync sibling-mount report filed the same day: a shared tool
# assuming the workspace root is always an ancestor of the project.
BASE="$(basename "$REPO")"

# ONE implementation, shared with every python tool. A second copy of this logic in
# bash is exactly how the two drifted: the sibling-mount shape was handled in one
# and not the other, and the push line came out as a Linux path Dan could not paste.
WINPATH="$(win_path "$REPO")"

echo
echo "  Unpushed commits:"
git log --oneline @{u}..HEAD 2>/dev/null | sed 's/^/    /' || git log --oneline | sed 's/^/    /'
echo
echo "  PASTE THIS IN POWERSHELL TO PUSH:"
echo
push_line "$WINPATH" "$BRANCH"
echo
