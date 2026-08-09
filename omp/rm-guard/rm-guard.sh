#!/usr/bin/env bash
# Refuse deletions at, inside, or above configured protected paths; pass other
# invocations to the real `rm`. Paths default to /workspace/.git and can be
# overridden with the colon-separated RM_GUARD_PROTECTED_PATHS variable.
#
# This prevents accidental deletion, not deliberate bypass, and is not a
# security boundary.
set -euo pipefail

REAL_RM="/usr/bin/rm.real"

canon() {
    # Canonicalize all path forms, including symlinks and nonexistent targets.
    realpath -m -- "$1"
}

IFS=':' read -r -a _raw_protected <<< "${RM_GUARD_PROTECTED_PATHS:-/workspace/.git}"
PROTECTED=()
for p in "${_raw_protected[@]}"; do
    [ -z "$p" ] && continue
    PROTECTED+=("$(canon "$p")")
done

is_self_or_ancestor() {
    # true if $1 == $2, or $1 is an ancestor directory of $2
    local anc="$1" desc="$2"
    [ "$anc" = "/" ] && return 0
    case "$desc" in
        "$anc") return 0 ;;
        "$anc"/*) return 0 ;;
        *) return 1 ;;
    esac
}

if [ "$#" -eq 0 ]; then
    exec "$REAL_RM"
fi

pass=()
blocked=0
end_of_opts=0

for arg in "$@"; do
    if [ "$end_of_opts" -eq 0 ] && [ "$arg" = "--" ]; then
        end_of_opts=1
        pass+=("$arg")
        continue
    fi
    if [ "$end_of_opts" -eq 0 ] && [ "$arg" != "-" ] && [[ "$arg" == -* ]]; then
        # option flag (e.g. -rf, --recursive, --interactive=once) — rm has no
        # options that consume a following argv as a value, so a simple
        # leading-dash check is sufficient to separate flags from operands.
        pass+=("$arg")
        continue
    fi

    resolved="$(canon "$arg")"
    hit=""
    for p in "${PROTECTED[@]}"; do
        if is_self_or_ancestor "$p" "$resolved"; then
            hit="removing inside/at protected path '$p'"
            break
        fi
        if is_self_or_ancestor "$resolved" "$p"; then
            hit="'$arg' is an ancestor of protected path '$p'"
            break
        fi
    done

    if [ -n "$hit" ]; then
        echo "rm: refusing to remove '$arg' ($hit)" >&2
        blocked=1
        continue
    fi
    pass+=("$arg")
done

if [ "${#pass[@]}" -eq 0 ]; then
    # every operand named was protected; nothing left to hand to the real rm
    # (calling it bare here would print a misleading "missing operand"
    # instead of the refusal(s) already printed above).
    exit 1
fi

rc=0
"$REAL_RM" "${pass[@]}" || rc=$?

if [ "$blocked" -eq 1 ] && [ "$rc" -eq 0 ]; then
    rc=1
fi
exit "$rc"
