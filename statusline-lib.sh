#!/usr/bin/env bash
# Shared helpers for statusline-command.sh and subagent-statusline.sh (layout "C: two-line HUD").

E=$'\033'
RST="${E}[0m"; BOLD="${E}[1m"
C_DIM="${E}[38;5;244m"; C_FAINT="${E}[38;5;238m"; C_MODEL="${E}[38;5;173m"; C_BLUE="${E}[38;5;75m"; C_PURPLE="${E}[38;5;141m"
C_GREEN="${E}[38;5;78m"; C_YELLOW="${E}[38;5;220m"; C_ORANGE="${E}[38;5;208m"; C_RED="${E}[38;5;196m"; C_TAN="${E}[38;5;180m"; C_CYAN="${E}[38;5;80m"

ctx_color() { if [ "$1" -lt 50 ]; then printf '%s' "$C_GREEN"; elif [ "$1" -le 80 ]; then printf '%s' "$C_YELLOW"; else printf '%s' "$C_RED"; fi; }

effort_color() {
  case "$1" in low) printf '%s' "$C_DIM" ;; medium) printf '%s' "$C_YELLOW" ;; high|xhigh) printf '%s' "$C_ORANGE" ;; max) printf '%s' "$C_RED" ;; *) printf '%s' "$C_DIM" ;; esac
}
effort_short() { case "$1" in medium) printf med ;; xhigh) printf xhi ;; *) printf '%s' "$1" ;; esac; }

# style A pieces: segment separator and ▰▱ gauge
SEP=" ${E}[38;5;240m│${RST} "
gauge() {  # gauge <pct> <width>
  local p=$1 w=$2 n i out=""
  n=$(( (p * w + 50) / 100 ))
  for ((i = 0; i < w; i++)); do if [ "$i" -lt "$n" ]; then out="$out▰"; else out="$out▱"; fi; done
  printf '%s%s%s' "$(ctx_color "$p")" "$out" "$RST"
}

# bar <pct> <width>: filled ━ in context colour, empty ─ faint
bar() {
  local p=$1 w=$2 n i out="" col
  n=$(( (p * w + 50) / 100 )); col=$(ctx_color "$p")
  out="$col"; for ((i = 0; i < n; i++)); do out="$out━"; done
  out="$out$C_FAINT"; for ((i = n; i < w; i++)); do out="$out─"; done
  printf '%s%s' "$out" "$RST"
}

tok() {  # 76000 -> 76k, 1000000 -> 1M
  local n=$1
  if [ "$n" -ge 1000000 ]; then
    if [ $((n % 1000000)) -eq 0 ]; then printf '%sM' $((n / 1000000)); else printf '%s.%sM' $((n / 1000000)) $(((n % 1000000) / 100000)); fi
  else printf '%sk' $(((n + 500) / 1000)); fi
}

dur() {  # seconds -> 45s / 23m / 1h12m
  local s=$1
  if [ "$s" -ge 3600 ]; then printf '%sh%02dm' $((s / 3600)) $(((s % 3600) / 60))
  elif [ "$s" -ge 60 ]; then printf '%sm' $((s / 60))
  else printf '%ss' "$s"; fi
}

tilde() { case "$1" in "$HOME") printf '~' ;; "$HOME"/*) printf '~/%s' "${1#"$HOME"/}" ;; *) printf '%s' "$1" ;; esac; }

# shorten_dir <path> <keep>: keep last <keep> components when the path is long
shorten_dir() {
  local wd keep=$2; wd=$(tilde "$1")
  local IFS='/'; local -a parts; read -r -a parts <<<"$wd"
  if [ "${#parts[@]}" -gt $((keep + 1)) ]; then
    local out="…" i
    for ((i = ${#parts[@]} - keep; i < ${#parts[@]}; i++)); do out="$out/${parts[i]}"; done
    wd=$out
  fi
  printf '%s' "$wd"
}

short_model() {  # claude-sonnet-5-5 -> sonnet 5.5 ; claude-haiku-4-5-20251001 -> haiku 4.5
  local m=${1#claude-}
  printf '%s' "$m" | sed -E 's/\[.*\]$//; s/-[0-9]{8}$//; s/^([a-z]+)-([0-9]+)-([0-9]+)$/\1 \2.\3/; s/^([a-z]+)-([0-9]+)$/\1 \2/'
}

# git_info <dir> -> sets G_BRANCH G_WT G_COMMON (empty when not a repo)
git_info() {
  G_BRANCH=""; G_WT=""; G_COMMON=""
  [ -d "$1" ] || return 1
  local out gd gcd top
  out=$(git --no-optional-locks -C "$1" rev-parse --abbrev-ref HEAD --path-format=absolute --git-dir --git-common-dir --show-toplevel 2>/dev/null) || return 1
  { read -r G_BRANCH; read -r gd; read -r gcd; read -r top; } <<<"$out"
  if [ "$G_BRANCH" = "HEAD" ]; then G_BRANCH=$(git --no-optional-locks -C "$1" rev-parse --short HEAD 2>/dev/null); fi
  G_COMMON=$gcd
  [ -n "$gd" ] && [ -n "$gcd" ] && [ "$gd" != "$gcd" ] && G_WT=${top##*/}
  return 0
}

# pr_lookup <dir> <branch> <common-dir> -> sets PR_N PR_S from a 60s cache refreshed in the background.
# PR_FOUND is "yes", "none" (gh confirmed the branch has no PR) or "" (unknown: no gh, or nothing cached yet).
pr_lookup() {
  PR_N=""; PR_S=""; PR_FOUND=""
  local dir=$1 br=$2 gcd=$3
  command -v gh >/dev/null 2>&1 || return 0
  [ -n "$gcd" ] && [ -n "$br" ] || return 0
  local cdir="${XDG_CACHE_HOME:-$HOME/.cache}/claude-statusline" key cf now mt
  key=$(printf '%s|%s' "$gcd" "$br" | cksum | cut -d' ' -f1)
  cf="$cdir/pr-$key"
  mkdir -p "$cdir" 2>/dev/null
  now=$(date +%s); mt=$(stat -c %Y "$cf" 2>/dev/null || echo 0)
  if [ $((now - mt)) -ge 60 ]; then
    touch "$cf" 2>/dev/null  # claim the refresh so parallel renders don't duplicate it
    (
      cd "$dir" 2>/dev/null || exit 0
      # look the PR up by branch name: `gh pr view` follows the upstream, which for branches
      # created off origin/main is main itself. Newest PR for the branch, any state.
      r=$(timeout 15 gh pr list --head "$br" --state all --limit 1 --json number,state,isDraft,reviewDecision \
            -q '.[0] // empty | "\(.number) \(.state) \(.isDraft) \(.reviewDecision)"' 2>/dev/null) \
        || exit 0  # network/auth hiccup: keep the last known answer
      r=${r:-none}
      tmp="$cf.$$.tmp"
      printf '%s\n' "$r" >"$tmp" 2>/dev/null && mv -f "$tmp" "$cf" 2>/dev/null
    ) </dev/null >/dev/null 2>&1 &
    disown 2>/dev/null
  fi
  local n st dr rv
  read -r n st dr rv <"$cf" 2>/dev/null
  [ "$n" = "none" ] && PR_FOUND=none
  case "$n" in ''|*[!0-9]*) return 0 ;; esac
  PR_FOUND=yes; PR_N=$n; PR_S=$(pr_state "$st" "$dr" "$rv")
}

# pr_state <STATE> <isDraft> <reviewDecision> -> approved|changes_requested|draft|merged|closed|open
pr_state() {
  case "$1" in MERGED) echo merged; return ;; CLOSED) echo closed; return ;; esac
  [ "$2" = "true" ] && { echo draft; return; }
  case "$3" in APPROVED) echo approved ;; CHANGES_REQUESTED) echo changes_requested ;; *) echo open ;; esac
}

# pr_format <number> <state> [short]: "PR #n ✓ approved" (long) or "#n ✓" (short)
pr_format() {
  local c g txt
  case "$2" in
    approved) c=$C_GREEN; g="✓"; txt="approved" ;;
    changes_requested) c=$C_ORANGE; g="±"; txt="changes requested" ;;
    draft) c=$C_DIM; g="◌"; txt="draft" ;;
    merged) c=$C_PURPLE; g="⊕"; txt="merged" ;;
    closed) c=$C_RED; g="✗"; txt="closed" ;;
    *) c=$C_GREEN; g="○"; txt="open" ;;
  esac
  if [ -n "$3" ]; then printf '%s#%s %s%s' "$c" "$1" "$g" "$RST"; else printf '%sPR #%s %s %s%s' "$c" "$1" "$g" "$txt" "$RST"; fi
}

# term_cols: width of the terminal Claude runs in. Walks up the process tree via /proc (no forks)
# to the first ancestor with a controlling tty, then asks that tty for its size.
term_cols() {
  local p=$$ stat rest ppid tty_nr c _
  while [ -n "$p" ] && [ "$p" -gt 1 ]; do
    read -r stat <"/proc/$p/stat" 2>/dev/null || break
    rest=${stat##*) }                              # skip "pid (comm) " — comm may contain spaces
    read -r _ ppid _ _ tty_nr _ <<<"$rest"
    if [ "${tty_nr:-0}" -ne 0 ]; then
      c=$(stty -F "/proc/$p/fd/0" size 2>/dev/null) && c=${c#* } && [ "${c:-0}" -gt 0 ] && { printf '%s' "$c"; return; }
    fi
    p=$ppid
  done
  printf '%s' "${COLUMNS:-0}"
}

vis_len() { local s; s=$(printf '%s' "$1" | sed -E 's/\x1b\[[0-9;]*m//g'); printf '%s' "${#s}"; }

# lr <left> <right> <width>: right-align <right> within <width>; falls back to a 3-space gap when it doesn't fit
lr() {
  local l=$1 r=$2 w=$3 gap
  [ -n "$r" ] || { printf '%s' "$l"; return; }
  gap=$(( w - $(vis_len "$l") - $(vis_len "$r") ))
  [ "$gap" -lt 3 ] && gap=3
  printf '%s%*s%s' "$l" "$gap" '' "$r"
}

# branch_diff <dir> -> sets BD_BASE BD_ADD BD_DEL: lines this branch changes vs the default branch,
# committed and uncommitted (diff from the merge-base to the working tree), i.e. roughly the PR size.
branch_diff() {
  BD_BASE=""; BD_ADD=0; BD_DEL=0
  local g=(git --no-optional-locks -C "$1") ref mb stat
  ref=$("${g[@]}" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)
  if [ -z "$ref" ]; then
    for ref in origin/main origin/master main master ""; do
      [ -n "$ref" ] && "${g[@]}" rev-parse -q --verify "$ref^{commit}" >/dev/null 2>&1 && break
    done
  fi
  [ -n "$ref" ] || return 1
  mb=$("${g[@]}" merge-base "$ref" HEAD 2>/dev/null) || return 1
  stat=$("${g[@]}" diff --shortstat "$mb" 2>/dev/null) || return 1
  BD_BASE=${ref#origin/}
  [[ $stat =~ ([0-9]+)\ insertion ]] && BD_ADD=${BASH_REMATCH[1]}
  [[ $stat =~ ([0-9]+)\ deletion ]] && BD_DEL=${BASH_REMATCH[1]}
  return 0
}

# wt_label <worktree-name>: agent worktrees (agent-<hex>) get a stable funny name plus the last 3 hex chars,
# e.g. agent-aabc76ec187ad63fe -> sleepy-otter-3fe. Other worktree names are kept as they are.
WT_ADJ=(sleepy fuzzy grumpy sneaky wobbly spicy cosmic soggy bouncy salty zesty dizzy crispy jolly nifty sassy
        chunky giddy lumpy perky quirky rusty snappy tipsy wiggly zany peppy loopy mighty frosty toasty cheeky)
WT_NOUN=(otter llama wombat badger goose panda gecko walrus yak ferret narwhal moose lemur koala puffin hippo
         sloth beaver quokka bison tapir mongoose platypus raccoon pelican iguana weasel squid newt marmot heron dingo)
wt_label() {
  local n=$1 hex
  if [[ $n =~ ^agent-([0-9a-f]{6,})$ ]]; then
    hex=${BASH_REMATCH[1]}
    printf '%s-%s-%s' "${WT_ADJ[$(( 16#${hex:0:2} % ${#WT_ADJ[@]} ))]}" "${WT_NOUN[$(( 16#${hex:2:2} % ${#WT_NOUN[@]} ))]}" "${hex: -3}"
  else
    printf '%s' "$n"
  fi
}
