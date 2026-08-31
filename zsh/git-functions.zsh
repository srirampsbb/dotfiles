# ==============================================================================
# Git Worktree Automation
# ==============================================================================
# Prevent alias/function name collisions during shell reload.
unalias cdr cdw gwo gwa gwl gbs 2>/dev/null

# Fuzzy switch to a repository under ~/code/repos
#
# Usage: cdr
cdr() {
  local repos_root="$HOME/code/repos"

  if ! command -v fzf >/dev/null 2>&1; then
    echo "Error: 'fzf' is required but was not found in PATH."
    return 1
  fi

  if [[ ! -d "$repos_root" ]]; then
    echo "Error: Repos directory '$repos_root' does not exist."
    return 1
  fi

  local selected_repo
  selected_repo="$(
    find "$repos_root" -mindepth 1 -maxdepth 1 -type d 2>/dev/null \
      | sort \
      | fzf --prompt="Repo > " --height=40% --reverse
  )"

  if [[ -z "$selected_repo" ]]; then
    return 1
  fi

  cd "$selected_repo" || return 1
}

# Fuzzy switch to a worktree under ~/code/worktrees
#
# Usage: cdw
cdw() {
  gwl "$@"
}

# Worktree menu shortcut
#
# Usage: gwo
gwo() {
  gwl "$@"
}

# Usage: gwa
gwa() {
  local repos_root="$HOME/code/repos"
  local worktrees_root="$HOME/code/worktrees"

  if ! command -v fzf >/dev/null 2>&1; then
    echo "❌ Error: 'fzf' is required but was not found in PATH."
    return 1
  fi

  if [[ ! -d "$repos_root" ]]; then
    echo "❌ Error: Repos directory '$repos_root' does not exist."
    return 1
  fi

  local repo_list
  repo_list="$(
    find "$repos_root" -mindepth 1 -type d -name .git -prune 2>/dev/null \
      | sed "s#^$repos_root/##" \
      | sed 's#/.git$##' \
      | sort
  )"

  if [[ -z "$repo_list" ]]; then
    echo "❌ Error: No git repositories found under '$repos_root'."
    return 1
  fi

  local selected_repo_rel
  selected_repo_rel="$(printf "%s\n" "$repo_list" | fzf --prompt="Repo > " --height=40% --reverse)"
  if [[ -z "$selected_repo_rel" ]]; then
    echo "❌ Error: No repository selected."
    return 1
  fi

  local selected_repo_path="$repos_root/$selected_repo_rel"
  if ! cd "$selected_repo_path"; then
    echo "❌ Error: Failed to switch to repository '$selected_repo_path'."
    return 1
  fi

  echo "🔄 Fetching latest refs from all remotes..."
  local fetch_all_output
  if ! fetch_all_output="$(git fetch --all --prune 2>&1)"; then
    echo "❌ Error: Failed to fetch remotes in '$selected_repo_path'."
    echo "$fetch_all_output"
    return 1
  fi

  local remote_branches
  remote_branches="$(git branch -r --format='%(refname:short)' | grep -v ' -> ' | sort -u)"
  if [[ -z "$remote_branches" ]]; then
    echo "❌ Error: No remote branches found in '$selected_repo_path'."
    return 1
  fi

  local selected_remote_branch
  selected_remote_branch="$(printf "%s\n" "$remote_branches" | fzf --prompt="Remote branch > " --height=40% --reverse)"
  if [[ -z "$selected_remote_branch" ]]; then
    echo "❌ Error: No remote branch selected."
    return 1
  fi

  local selected_remote="${selected_remote_branch%%/*}"
  local selected_branch="${selected_remote_branch#*/}"
  local fetch_branch_log
  fetch_branch_log="$(mktemp)"

  echo "🔄 Fetching latest for '$selected_remote_branch' in background..."
  git fetch "$selected_remote" "$selected_branch" >"$fetch_branch_log" 2>&1 &
  local fetch_pid=$!

  local worktree_name
  read "worktree_name?Worktree name (relative to $worktrees_root): "
  if [[ -z "$worktree_name" ]]; then
    wait "$fetch_pid" >/dev/null 2>&1
    rm -f "$fetch_branch_log"
    echo "❌ Error: Worktree name is required."
    return 1
  fi

  if [[ "$worktree_name" == */* ]]; then
    wait "$fetch_pid" >/dev/null 2>&1
    rm -f "$fetch_branch_log"
    echo "❌ Error: Worktree name must be a single directory name (no '/')."
    return 1
  fi

  if ! mkdir -p "$worktrees_root" 2>/dev/null; then
    wait "$fetch_pid" >/dev/null 2>&1
    rm -f "$fetch_branch_log"
    echo "❌ Error: Failed to ensure worktrees directory '$worktrees_root'."
    return 1
  fi

  local target_path="$worktrees_root/$worktree_name"
  if [[ -e "$target_path" ]]; then
    wait "$fetch_pid" >/dev/null 2>&1
    rm -f "$fetch_branch_log"
    echo "❌ Error: Path '$target_path' already exists."
    return 1
  fi

  if ! wait "$fetch_pid"; then
    echo "❌ Error: Failed to fetch '$selected_remote_branch'."
    cat "$fetch_branch_log"
    rm -f "$fetch_branch_log"
    return 1
  fi
  rm -f "$fetch_branch_log"

  if ! git show-ref --verify --quiet "refs/remotes/$selected_remote_branch"; then
    echo "❌ Error: Remote branch ref 'refs/remotes/$selected_remote_branch' does not exist after fetch."
    return 1
  fi

  local add_output
  echo "🌳 Creating worktree from latest '$selected_remote_branch'..."
  if ! add_output="$(git worktree add --detach "$target_path" "$selected_remote_branch" 2>&1)"; then
    echo "❌ Error: Failed to create worktree."
    echo "$add_output"
    return 1
  fi

  if ! cd "$target_path"; then
    echo "❌ Error: Worktree created but failed to switch to '$target_path'."
    return 1
  fi

  echo "✅ Worktree created successfully."
  echo "📦 Repo: $selected_repo_path"
  echo "🌿 Branch: $selected_remote_branch"
  echo "🌳 Worktree: $target_path"
  echo "📍 HEAD:"
  if ! git --no-pager log -1 --decorate --oneline; then
    echo "❌ Error: Failed to print HEAD commit."
    return 1
  fi
}

# List recent worktrees with repo, remote branch, and last modified time
#
# Usage: gwl
gwl() {
  emulate -L zsh
  setopt localoptions noxtrace
  set +x 2>/dev/null
  functions +t gwl 2>/dev/null

  local worktrees_root="$HOME/code/worktrees"
  local legacy_worktrees_root="$HOME/code/wortkrees"
  local active_worktrees_root=""
  local stat_mode=""
  local date_mode=""

  if [[ -d "$worktrees_root" ]]; then
    active_worktrees_root="$worktrees_root"
  elif [[ -d "$legacy_worktrees_root" ]]; then
    active_worktrees_root="$legacy_worktrees_root"
  else
    echo "❌ Error: Neither '$worktrees_root' nor '$legacy_worktrees_root' exists."
    return 1
  fi

  local -a worktrees
  worktrees=("${(@f)$(find "$active_worktrees_root" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)}")

  if (( ${#worktrees[@]} == 0 )); then
    echo "❌ Error: No worktrees found under '$active_worktrees_root'."
    return 1
  fi

  if stat -f "%m" "$active_worktrees_root" >/dev/null 2>&1; then
    stat_mode="bsd"
  elif stat -c "%Y" "$active_worktrees_root" >/dev/null 2>&1; then
    stat_mode="gnu"
  else
    echo "❌ Error: Unable to determine a compatible 'stat' format."
    return 1
  fi

  if date -r 0 '+%Y-%m-%d %H:%M:%S' >/dev/null 2>&1; then
    date_mode="bsd"
  elif date -d "@0" '+%Y-%m-%d %H:%M:%S' >/dev/null 2>&1; then
    date_mode="gnu"
  else
    echo "❌ Error: Unable to determine a compatible 'date' format."
    return 1
  fi

  local -a rows
  local wt mtime
  for wt in "${worktrees[@]}"; do
    if [[ "$stat_mode" == "bsd" ]]; then
      mtime="$(stat -f "%m" "$wt" 2>/dev/null)" || continue
    else
      mtime="$(stat -c "%Y" "$wt" 2>/dev/null)" || continue
    fi
    rows+=("${mtime}|${wt}")
  done

  if (( ${#rows[@]} == 0 )); then
    echo "❌ Error: Unable to read worktree metadata under '$active_worktrees_root'."
    return 1
  fi

  local -a sorted_rows
  sorted_rows=("${(@On)rows}")

  local limit=20
  if (( ${#sorted_rows[@]} < limit )); then
    limit=${#sorted_rows[@]}
  fi

  local i row epoch wt_path
  local -a names repos branches times paths

  for ((i = 1; i <= limit; i++)); do
    row="${sorted_rows[$i]}"
    epoch="${row%%|*}"
    wt_path="${row#*|}"

    local wt_name="${wt_path:t}"
    local repo_display="unknown"
    local branch_display="detached/unknown"

    if git -C "$wt_path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      local remote_url
      remote_url="$(git -C "$wt_path" remote get-url --all origin 2>/dev/null | sed -n '1p')"
      if [[ -n "$remote_url" ]]; then
        repo_display="${remote_url%%\?*}"
        repo_display="${repo_display%%#*}"
        repo_display="${repo_display%/}"
        repo_display="${repo_display:t}"
        repo_display="${repo_display%.git}"
      fi

      local upstream_branch
      upstream_branch="$(git -C "$wt_path" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)"
      if [[ -n "$upstream_branch" ]]; then
        branch_display="$upstream_branch"
      else
        local pointed_remote
        pointed_remote="$(git -C "$wt_path" for-each-ref --format='%(refname:short)' --points-at HEAD refs/remotes 2>/dev/null | sed -n '1p')"
        if [[ -n "$pointed_remote" ]]; then
          branch_display="$pointed_remote"
        fi
      fi
    fi

    names+=("$wt_name")
    repos+=("$repo_display")
    branches+=("$branch_display")
    if [[ "$date_mode" == "bsd" ]]; then
      times+=("$(date -r "$epoch" '+%Y-%m-%d %H:%M:%S')")
    else
      times+=("$(date -d "@$epoch" '+%Y-%m-%d %H:%M:%S')")
    fi
    paths+=("$wt_path")

  done

  if ! command -v fzf >/dev/null 2>&1; then
    echo "❌ Error: 'fzf' is required to choose a worktree from the menu."
    return 1
  fi

  local name_col=26
  local repo_col=52
  local branch_col=42
  local sep=$'\x1f'

  local -a menu_lines
  local header
  header="$(printf "%-${name_col}s  %-${repo_col}s  %-${branch_col}s  %s" \
    "WORKTREE" "REPO" "REMOTE BRANCH" "LAST MODIFIED")"
  menu_lines=("${header}${sep}__HEADER__")

  local name_view repo_view branch_view display_line
  for ((i = 1; i <= ${#names[@]}; i++)); do
    name_view="${names[$i]}"
    repo_view="${repos[$i]}"
    branch_view="${branches[$i]}"

    if (( ${#name_view} > name_col )); then
      name_view="${name_view[1,$((name_col - 1))]}…"
    fi
    if (( ${#repo_view} > repo_col )); then
      repo_view="${repo_view[1,$((repo_col - 1))]}…"
    fi
    if (( ${#branch_view} > branch_col )); then
      branch_view="${branch_view[1,$((branch_col - 1))]}…"
    fi

    display_line="$(printf "%-${name_col}s  %-${repo_col}s  %-${branch_col}s  %s" \
      "$name_view" "$repo_view" "$branch_view" "${times[$i]}")"
    menu_lines+=("${display_line}${sep}${paths[$i]}")
  done

  local selected_line selected_path
  selected_line="$(
    printf "%s\n" "${menu_lines[@]}" \
      | fzf \
        --prompt="Select worktree > " \
        --height=55% \
        --reverse \
        --delimiter="$sep" \
        --with-nth=1 \
        --header-lines=1
  )"

  if [[ -z "$selected_line" ]]; then
    return 1
  fi

  selected_path="${selected_line##*$sep}"
  if ! cd "$selected_path"; then
    echo "❌ Error: Failed to switch to worktree '$selected_path'."
    return 1
  fi
}

# Search remote git branches using fuzzy matching (fzf) or regex (grep)
#
# Usage:
#   gbs <search_term_or_regex>
#
# Examples:
#   gbs master          # Find branches matching "master"
#   gbs "feat.*auth"    # Find branches matching regex
#   git checkout $(gbs feature)  # Select branch and check it out
gbs() {
  # Store the first argument passed to the command as the search pattern
  local search_term="$1"

  # Check if a search term was provided; exit with a usage warning if empty
  if [[ -z "$search_term" ]]; then
    echo "Usage: gbs <pattern_or_search_term>"
    return 1
  fi

  # Silently fetch and prune deleted remote tracking branches
  git fetch --prune >/dev/null 2>&1

  # Check if fzf is installed to enable interactive fuzzy finding
  if command -v fzf >/dev/null 2>&1; then
    # Interactive Fuzzy Mode:
    # - Lists formatted remote branch names without extra metadata
    # - Pre-populates fzf with the search query
    # - Auto-selects if only 1 match exists (--select-1)
    # - Exits cleanly without error if no match is found (--exit-0)
    git branch -r --format="%(refname:short)" | fzf --query="$search_term" --select-1 --exit-0
  else
    # Non-Interactive Fallback Mode:
    # - Uses case-insensitive extended regex matching via grep
    git branch -r --format="%(refname:short)" | grep -iE "$search_term"
  fi
}
