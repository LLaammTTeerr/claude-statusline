#!/usr/bin/env bash
# Status line, two lines, style A (│-separated segments) with the right side aligned to the terminal edge:
#   1: ◆ Model [effort] │ ▸ cwd │ ⎇ branch ⑂ worktree                               PR #n ✓ approved
#   2: ▰▰▰▱▱▱▱▱▱▱ 38% 76k/200k                 ⏱ 23m │ vs main +943 −13 │ 5h 41% 7d 18% │ cache ▲warm
# STATUSLINE_RIGHT_MARGIN defaults to SUBAGENT_STATUSLINE_RIGHT_MARGIN + 4: Claude Code indents this line by 2, while
# subagent rows get a 4-column prefix and `columns` = terminal width - 6. With these, both right edges land together.
# Never blocks on the network: PR info comes from a cached `gh pr list` refreshed in the background.
export LC_ALL=C.UTF-8
. "$(dirname "$0")/statusline-lib.sh"
input=$(cat)

IFS=$'\x1f' read -r sid model effort pct size used dur_ms r5 r7 observed warm dir prn prrs wtname < <(
  printf '%s' "$input" | jq -r '[
    (.session_id // ""),
    (.model.display_name // "?"),
    (.effort.level // ""),
    (.context_window.used_percentage // 0),
    (.context_window.context_window_size // 0),
    (.context_window.total_input_tokens // 0),
    (.cost.total_duration_ms // 0),
    (.rate_limits.five_hour.used_percentage // ""),
    (.rate_limits.seven_day.used_percentage // ""),
    (.prompt_cache.caching_observed == true),
    (.prompt_cache.warm == true),
    (.workspace.current_dir // .cwd // ""),
    (.pr.number // ""),
    (.pr.review_state // ""),
    (.worktree.name // "")
  ] | map(tostring) | join("\u001f")' 2>/dev/null
)
[ -n "$dir" ] || dir=$PWD

# remember this session's effort: subagents without their own effort level inherit it
if [ -n "$sid" ]; then
  ef="${XDG_CACHE_HOME:-$HOME/.cache}/claude-statusline/effort-$sid"
  [ "$(cat "$ef" 2>/dev/null)" = "$effort" ] || { mkdir -p "${ef%/*}" && printf '%s' "$effort" >"$ef"; } 2>/dev/null
fi
int() { local v; v=$(printf '%.0f' "${1:-0}" 2>/dev/null) || v=0; case "$v" in ''|*[!0-9]*) v=0 ;; esac; printf '%s' "$v"; }
pct=$(int "$pct"); [ "$pct" -gt 100 ] && pct=100
size=$(int "$size"); used=$(int "$used")
[ "$used" -eq 0 ] && [ "$size" -gt 0 ] && used=$((size * pct / 100))

# ---- line 1: where you are (left), PR (right) ----
r1=""; r2=()
id1="${BOLD}${C_MODEL}◆ ${model:-?}${RST}"
[ -n "$effort" ] && id1="$id1 $(effort_color "$effort")[${effort}]${RST}"
g=""

if git_info "$dir"; then
  wt=${wtname:-$G_WT}
  g="${C_BLUE}⎇ ${G_BRANCH}${RST}"
  [ -n "$wt" ] && g="$g ${C_PURPLE}⑂ $(wt_label "$wt")${RST}"
  # gh knows merged/closed state; Claude Code's .pr does not and can go stale, so it's only a fallback
  pr_lookup "$dir" "$G_BRANCH" "$G_COMMON"
  pr=""
  if [ -n "$PR_N" ]; then pr=$(pr_format "$PR_N" "$PR_S")
  elif [ -n "$prn" ] && [ "$PR_FOUND" != "none" ]; then pr=$(pr_format "$prn" "$(printf '%s' "$prrs" | tr 'A-Z' 'a-z')")
  fi
  r1=${pr:-${C_DIM}PR —${RST}}
fi

# ---- line 2: context gauge (left), session budget (right) ----
l2="$(gauge "$pct" 10) ${BOLD}$(ctx_color "$pct")${pct}%${RST}"
[ "$size" -gt 0 ] && l2="$l2 ${C_DIM}$(tok "$used")/$(tok "$size")${RST}"

dur_s=$(( $(int "$dur_ms") / 1000 ))
[ "$dur_s" -gt 0 ] && r2+=("${C_DIM}⏱ $(dur "$dur_s")${RST}")

# lines this branch changes vs the default branch (committed + uncommitted), hidden when there are none
if [ -n "$G_COMMON" ] && branch_diff "$dir" && [ $((BD_ADD + BD_DEL)) -gt 0 ]; then
  r2+=("${C_DIM}vs ${BD_BASE}${RST} ${C_GREEN}+${BD_ADD}${RST} ${C_RED}−${BD_DEL}${RST}")
fi

lim() { local v; v=$(int "$2"); if [ "$v" -ge 80 ]; then printf '%s' "$C_RED"; elif [ "$v" -ge 50 ]; then printf '%s' "$C_YELLOW"; else printf '%s' "$C_DIM"; fi; printf '%s %s%%%s' "$1" "$v" "$RST"; }
lims=""
[ -n "$r5" ] && lims="$(lim 5h "$r5")"
[ -n "$r7" ] && lims="${lims:+$lims }$(lim 7d "$r7")"
[ -n "$lims" ] && r2+=("$lims")

if [ "$observed" = "true" ]; then
  if [ "$warm" = "true" ]; then r2+=("${C_ORANGE}cache ▲warm${RST}"); else r2+=("${C_CYAN}cache ▽cold${RST}"); fi
fi

join_sep() { local out="" s; for s in "$@"; do [ -n "$s" ] && out="${out:+$out$SEP}$s"; done; printf '%s' "$out"; }

w=$(( $(term_cols) - ${STATUSLINE_RIGHT_MARGIN:-$(( ${SUBAGENT_STATUSLINE_RIGHT_MARGIN:-2} + 4 ))} ))
# folder path: keep 4 components, fewer when line 1 would not fit next to the PR
for keep in 4 2 1; do
  l1=$(join_sep "$id1" "${C_TAN}▸ $(shorten_dir "$dir" "$keep")${RST}" "$g")
  [ $(( $(vis_len "$l1") + $(vis_len "$r1") + 3 )) -le "$w" ] && break
done

printf '%s\n%s' "$(lr "$l1" "$r1" "$w")" "$(lr "$l2" "$(join_sep "${r2[@]}")" "$w")"
exit 0
