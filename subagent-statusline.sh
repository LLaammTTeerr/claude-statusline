#!/usr/bin/env bash
# Subagent rows, style A (│-separated), columns aligned across all agents:
#   ● name │ model [effort] │ ▰▰▱▱▱ pct │ ⎇ branch ⑂ worktree │ ▸ dir              #PR ✓ │ elapsed
# PR and elapsed are right-aligned to `columns` minus SUBAGENT_STATUSLINE_RIGHT_MARGIN (default 2).
# Input: {columns, tasks:[{id,name,type,status,label,startTime,model,effort,contextWindowSize,tokenCount,cwd}]}
# Output: one {"id":..., "content":...} JSON line per task.
export LC_ALL=C.UTF-8
. "$(dirname "$0")/statusline-lib.sh"
input=$(cat)
now_ms=$(( $(date +%s) * 1000 ))
cols=$(printf '%s' "$input" | jq -r '.columns // 0' 2>/dev/null)
case "$cols" in ''|*[!0-9]*|0) cols=$(term_cols) ;; esac
width=$(( cols - ${SUBAGENT_STATUSLINE_RIGHT_MARGIN:-2} ))
# effort the main session runs at (saved by statusline-command.sh); used when a task has no effort of its own
sid=$(printf '%s' "$input" | jq -r '.session_id // ""' 2>/dev/null)
inherit=""; [ -n "$sid" ] && inherit=$(cat "${XDG_CACHE_HOME:-$HOME/.cache}/claude-statusline/effort-$sid" 2>/dev/null)

tdir="${XDG_CACHE_HOME:-$HOME/.cache}/claude-statusline/tasks"
mkdir -p "$tdir" 2>/dev/null && find "$tdir" -type f -mmin +1440 -delete 2>/dev/null  # forget finish times after a day
fins=(); ids=(); sts=(); names=(); mods=(); effs=(); pcts=(); brs=(); wts=(); dirs=(); prs=(); prss=(); els=()
while IFS=$'\x1f' read -r id name status model effort tokens size start cwd; do
  [ -n "$id" ] || continue
  p=0
  if [ "${size:-0}" -gt 0 ] 2>/dev/null; then p=$(( tokens * 100 / size )); [ "$p" -gt 100 ] && p=100; fi
  m=""; [ -n "$model" ] && m=$(short_model "$model")
  case "$model" in *haiku*) effort="" ;; *) effort=${effort:-$inherit} ;; esac  # Haiku takes no effort setting
  br=""; wt=""; PR_N=""; PR_S=""
  if [ -n "$cwd" ] && git_info "$cwd"; then
    br=$G_BRANCH; wt=$G_WT
    pr_lookup "$cwd" "$G_BRANCH" "$G_COMMON"
  fi
  # finished agents: freeze the clock at the first render that saw them finished
  fin=0; end_ms=$now_ms
  case "$status" in running|in_progress|pending|"") ;; *)
    fin=1; ef="$tdir/end-$id"
    if ! read -r end_ms 2>/dev/null <"$ef"; then end_ms=$now_ms; printf '%s\n' "$now_ms" 2>/dev/null >"$ef"; fi ;;
  esac
  el=""
  if [ "${start:-0}" -gt 0 ] 2>/dev/null; then
    st=$start; [ "$st" -lt 100000000000 ] && st=$(( st * 1000 ))
    e=$(( (end_ms - st) / 1000 )); [ "$e" -lt 0 ] && e=0
    if [ "$e" -ge 60 ] && [ "$e" -lt 3600 ]; then el="$((e / 60))m$(printf '%02d' $((e % 60)))s"; else el=$(dur "$e"); fi
  fi
  fins+=("$fin"); ids+=("$id"); sts+=("$status"); names+=("$name"); mods+=("$m"); effs+=("$effort"); pcts+=("$p")
  # dir is left blank when it is just the worktree root (the wt: label already names it)
  brs+=("$br"); wts+=("${wt:+$(wt_label "$wt")}"); dirs+=("$( [ -n "$cwd" ] && [ "${cwd%/}" != "${cwd%/*}/$wt" -o -z "$wt" ] && shorten_dir "$cwd" 1)"); prs+=("${PR_N:+#$PR_N}"); prss+=("$PR_S"); els+=("$el")
done < <(printf '%s' "$input" | jq -r '
  .tasks[]? | [
    (.id // ""), (.name // .label // .type // "agent"), (.status // ""),
    (.model // ""), ((.effort // "") | tostring),
    ((.tokenCount // 0) | tostring), ((.contextWindowSize // 0) | tostring),
    ((.startTime // 0) | tostring), (.cwd // "")
  ] | join("\u001f")' 2>/dev/null)

maxw() { local m=0 v; for v in "$@"; do [ "${#v}" -gt "$m" ] && m=${#v}; done; printf '%s' "$m"; }
pad() { local t=$1 w=$2; printf '%s%*s' "$t" $((w - ${#t})) ''; }
mtags=(); for i in "${!ids[@]}"; do mtags+=("${mods[i]}${effs[i]:+ [${effs[i]}]}"); done
wn=$(maxw "${names[@]}"); wm=$(maxw "${mtags[@]}"); wb=$(maxw "${brs[@]}"); ww=$(maxw "${wts[@]}"); wd=$(maxw "${dirs[@]}"); we=$(maxw "${els[@]}")
wp=$(maxw — "${prs[@]}")
[ "$ww" -gt 0 ] && ww=$((ww + 2))  # "⑂ " prefix

for i in "${!ids[@]}"; do
  case "${sts[i]}" in
    running|in_progress|pending) si="${C_YELLOW}●" ;;
    completed|done|success)      si="${C_GREEN}✓" ;;
    failed|error|killed|stopped) si="${C_RED}✗" ;;
    *)                           si="${C_DIM}○" ;;
  esac
  p=${pcts[i]}
  row="${si}${RST} ${BOLD}$(pad "${names[i]}" "$wn")${RST}"
  if [ "$wm" -gt 0 ]; then
    mt="${C_MODEL}${mods[i]}${RST}"; [ -n "${effs[i]}" ] && mt="$mt $(effort_color "${effs[i]}")[${effs[i]}]${RST}"
    row="$row$SEP$mt$(printf '%*s' $((wm - ${#mtags[i]})) '')"
  fi
  row="$row$SEP$(gauge "$p" 5) $(ctx_color "$p")$(printf '%3s%%' "$p")${RST}"
  if [ "$wb" -gt 0 ]; then
    if [ -n "${brs[i]}" ]; then row="$row$SEP${C_BLUE}⎇ $(pad "${brs[i]}" "$wb")${RST}"; else row="$row$SEP$(pad '' $((wb + 2)))"; fi
    if [ "$ww" -gt 0 ]; then
      if [ -n "${wts[i]}" ]; then row="$row ${C_PURPLE}$(pad "⑂ ${wts[i]}" "$ww")${RST}"; else row="$row $(pad '' "$ww")"; fi
    fi
  fi
  if [ "$wd" -gt 0 ]; then
    if [ -n "${dirs[i]}" ]; then row="$row$SEP${C_TAN}▸ $(pad "${dirs[i]}" "$wd")${RST}"; fi  # blank: no dangling separator
  fi
  row="${row%"${row##*[! ]}"}"  # trim trailing padding; the right side is aligned separately
  if [ -n "${prs[i]}" ]; then
    right="$(printf '%*s' $((wp - ${#prs[i]})) '')$(pr_format "${prs[i]#\#}" "${prss[i]}" short)"
  else right="${C_DIM}$(printf '%*s' $((wp + 2)) —)${RST}"; fi
  [ "$we" -gt 0 ] && right="$right$SEP${C_DIM}$(printf '%*s' "$we" "${els[i]}")${RST}"
  line=$(lr "$row" "$right" "$width")
  if [ "${fins[i]}" = 1 ]; then  # finished: keep the status mark, dim the rest
    body=$(printf '%s' "${line#*"$si${RST}"}" | sed -E 's/\x1b\[[0-9;]*m//g')
    line="${si}${RST}${C_FAINT}${body}${RST}"
  fi
  jq -nc --arg id "${ids[i]}" --arg c "$line" '{id: $id, content: $c}'
done
exit 0
