# ==============================================================================
# Git Worktree Automation
# ==============================================================================
# Usage: gwa <dir-name> <branch-name> [base-ref]
gwa() {
  if [[ -z "$1" || -z "$2" ]]; then
    echo "❌ Error: Both directory name AND branch name are required."
    echo "Usage: gwa <dir-name> <branch-name> [base-ref]"
    return 1
  fi

  local dir_name="$1"
  local raw_branch="$2"
  local base_ref="$3"
  # Extract just the trailing folder name if a path was passed
  local clean_dir_name="$(basename "$dir_name")"
  local safe_dir_name="${clean_dir_name//\//-}"
  local target_path="$HOME/code/worktrees/$safe_dir_name"

  echo "🔄 Fetching latest refs from origin..."
  git fetch origin --prune

  echo "📁 Ensuring parent directory exists..."
  mkdir -p "$HOME/code/worktrees"

  if [[ -d "$target_path" ]]; then
    echo "❌ Error: Directory '$target_path' already exists."
    return 1
  fi

  local branch="${raw_branch#origin/}"
  # Case 1: Branch exists locally
  if git show-ref --verify --quiet "refs/heads/$branch"; then
    echo "ℹ️  Found local branch '$branch'. Creating worktree..."
    if git worktree add "$target_path" "$branch"; then
      echo "✅ Success: Attached to existing local branch '$branch'"
      cd "$target_path" || return
    else
      echo "❌ Error: Branch '$branch' may be checked out in another worktree."
      return 1
    fi

  # Case 2: Branch exists on origin
  elif git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
    echo "🚀 Found remote branch 'origin/$branch'. Creating tracking worktree..."
    if git worktree add -b "$branch" "$target_path" "origin/$branch"; then
      echo "✅ Success: Created worktree tracking 'origin/$branch'"
      cd "$target_path" || return
    else
      echo "❌ Error: Failed to create worktree tracking 'origin/$branch'."
      return 1
    fi

  # Case 3: Create brand new branch
  else
    if [[ -z "$base_ref" ]]; then
      echo "❌ Error: Branch '$branch' was not found locally or on origin."
      echo "👉 Please specify a base-ref to fork from."
      echo "Usage: gwa <dir-name> <branch-name> <base-ref>"
      return 1
    fi

    echo "🌱 Creating new branch '$branch' forked off '$base_ref'..."
    if git worktree add -b "$branch" "$target_path" "$base_ref"; then
      cd "$target_path" || return

      echo "📤 Publishing branch '$branch' to origin and setting upstream tracking..."
      if git push -u origin "$branch"; then
        echo "✅ Success: Created, published, and set tracking for '$branch'"
      else
        echo "⚠️ Worktree created, but failed to push '$branch' to origin."
      fi
    else
      echo "❌ Error: Failed to create worktree. Ensure base-ref '$base_ref' is valid."
      return 1
    fi
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
