# ==============================================================================
# Git Worktree Automation
# ==============================================================================

link-agent-files() {
	local src_dir="$HOME/.dotfiles/agents"
	if [[ ! -d "$src_dir" ]]; then
		echo "❌ Error: agents source directory '$src_dir' does not exist."
		return 1
	fi
	mkdir -p .cursor .opencode
	ln -sf "$src_dir/AGENTS.md" AGENTS.md
	rm -rf .cursor/skills .opencode/skills
	ln -s "$src_dir/skills" .cursor/skills
	ln -s "$src_dir/skills" .opencode/skills
	echo "Symlinked AGENTS.md and skills/ from $src_dir/ to .cursor/ and .opencode/"
}

# Checkout a Gerrit CR in a new worktree
#
# Parses a Gerrit change URL like:
#   https://nugerrit.ntnxdpro.com/c/main/+/592326
# and creates a new worktree under ~/code/worktrees with a local branch.
#
# Usage:
#   checkout-gerrit-cr <gerrit-change-url>
#
# Examples:
#   checkout-gerrit-cr "https://nugerrit.ntnxdpro.com/c/main/+/592326"
checkout-gerrit-cr() {
	setopt localoptions noxtrace

	if [[ $# -lt 1 ]] || [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
		cat <<'EOF'
Usage:
  checkout-gerrit-cr <gerrit-change-url>

Creates a new git worktree containing the given Gerrit Change Request (CR).
The repo must be checked out under ~/code/repos (matched by Gerrit project name).

The change URL must look like:
  https://nugerrit.ntnxdpro.com/c/<repo>/+/<change-number>

The worktree will be created under:
  ~/code/worktrees/<repo>-cr<change-number>

A local branch named 'cr-<change-number>' is created from the fetched patch set.
EOF
		return 1
	fi

	local url="$1"

	# Validate basic URL format
	if [[ "$url" != *nugerrit.ntnxdpro.com/c/*/+/* ]]; then
		echo "❌ Error: URL does not look like a nugerrit change URL."
		echo "   Expected: https://nugerrit.ntnxdpro.com/c/<repo>/+/<change-number>"
		return 1
	fi

	if [[ -z "${GERRIT_TOKEN:-}" ]]; then
		echo "❌ Error: GERRIT_TOKEN is not set."
		echo "   Set your Gerrit HTTP token in the environment (e.g. export GERRIT_TOKEN=... in ~/.zshrc or a secrets file) and retry."
		return 1
	fi

	if [[ -z "${GERRIT_USERNAME:-}" ]]; then
		echo "❌ Error: GERRIT_USERNAME is not set."
		echo "   Set your Gerrit username in the environment (e.g. export GERRIT_USERNAME=... in ~/.zshrc) and retry."
		return 1
	fi

	if ! command -v jq >/dev/null 2>&1; then
		echo "❌ Error: 'jq' is required but was not found in PATH."
		return 1
	fi

	# Extract repo and change number from URL
	local repo
	repo="$(echo "$url" | sed -E 's|.*/c/([^/]+)/.*|\1|')"

	local change_num
	change_num="$(echo "$url" | grep -oE '[0-9]+' | tail -1)"

	if [[ -z "$repo" ]] || [[ -z "$change_num" ]]; then
		echo "❌ Error: Could not parse repo and change number from URL."
		return 1
	fi

	local last_two=${change_num: -2}
	local ref_base="refs/changes/$last_two/$change_num"

	local worktrees_root="$HOME/code/worktrees"
	local target_path="$worktrees_root/${repo}-cr${change_num}"
	local branch_name="cr-${change_num}"

	# Find the local clone of this repo under ~/code/repos by matching the
	# Gerrit project name (last path segment of origin) against the CR URL.
	local repos_root="$HOME/code/repos"
	local repo_path=""
	local candidate origin_url origin_name
	while IFS= read -r candidate; do
		candidate="${candidate%/.git}"
		origin_url="$(git -C "$candidate" remote get-url origin 2>/dev/null)" || continue
		origin_name="${origin_url%/}"
		origin_name="${origin_name%.git}"
		origin_name="${origin_name:t}"
		if [[ "$origin_name" == "$repo" ]]; then
			repo_path="$candidate"
			break
		fi
	done < <(find "$repos_root" -name .git -prune 2>/dev/null)

	if [[ -z "$repo_path" ]]; then
		echo "❌ Error: Repo '$repo' is not checked out in $repos_root."
		return 1
	fi

	# Check if worktree path already exists
	if [[ -e "$target_path" || -L "$target_path" ]]; then
		echo "❌ Error: Worktree path '$target_path' already exists."
		return 1
	fi

	# Check for duplicate branch across existing worktrees
	local existing
	existing="$(git -C "$repo_path" worktree list --porcelain 2>/dev/null | grep -Fx "branch refs/heads/$branch_name")"
	if [[ -n "$existing" ]]; then
		echo "❌ Error: Branch '$branch_name' is already checked out in a worktree."
		return 1
	fi

	echo "🔄 Fetching change $change_num from Gerrit..."
	local fetch_output
	local dst_ref="refs/gerrit-tmp/cr-${change_num}"

	# Ask the Gerrit REST API for the current (latest) patch set
	local gerrit_user="$GERRIT_USERNAME"
	local api_body api_json latest_sha latest_ps
	if ! api_body="$(
		curl -sS --fail -K - <<EOF
url = "https://nugerrit.ntnxdpro.com/a/changes/$change_num?o=CURRENT_REVISION"
user = "$gerrit_user:$GERRIT_TOKEN"
header = "Accept: application/json"
EOF
		2>&1
	)"; then
		echo "❌ Error: Gerrit REST API request failed for change $change_num."
		echo "$api_body"
		return 1
	fi

	# Strip Gerrit's ")]}'" XSSI prefix line, then read current revision and its patch set number
	api_json="$(printf '%s\n' "$api_body" | sed "1s/^)]}'//")"
	latest_sha="$(printf '%s' "$api_json" | jq -r '.current_revision // empty' 2>/dev/null)"
	latest_ps="$(printf '%s' "$api_json" | jq -r '.revisions[.current_revision]._number // empty' 2>/dev/null)"
	if [[ -z "$latest_sha" || -z "$latest_ps" ]]; then
		echo "❌ Error: Could not determine the latest patch set for change $change_num from the Gerrit REST API."
		return 1
	fi

	# Fetch the latest patch set over HTTPS, authenticating with GERRIT_TOKEN via an
	# env-supplied git config so the token isn't put in argv or the remote URL
	local ref_latest="$ref_base/$latest_ps"
	local gerrit_url="https://nugerrit.ntnxdpro.com/a/$repo"
	local basic_auth
	basic_auth="$(printf '%s:%s' "$gerrit_user" "$GERRIT_TOKEN" | base64 | tr -d '\n')"
	echo "   Latest patch set: $latest_ps ($latest_sha)"
	if ! fetch_output="$(GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http.extraHeader \
		GIT_CONFIG_VALUE_0="Authorization: Basic $basic_auth" \
		git -C "$repo_path" fetch "$gerrit_url" "$ref_latest:$dst_ref" 2>&1)"; then
		echo "❌ Error: Failed to fetch '$ref_latest' from Gerrit."
		echo "$fetch_output"
		return 1
	fi

	local fetched_sha
	fetched_sha="$(git -C "$repo_path" rev-parse "$dst_ref" 2>/dev/null)"
	if [[ "$fetched_sha" != "$latest_sha" ]]; then
		echo "❌ Error: Fetched commit $fetched_sha does not match Gerrit's latest revision $latest_sha."
		return 1
	fi

	echo "🌳 Creating worktree '$target_path' with branch '$branch_name'..."
	local add_output
	if ! add_output="$(git -C "$repo_path" worktree add -b "$branch_name" "$target_path" "$dst_ref" 2>&1)"; then
		echo "❌ Error: Failed to create worktree."
		echo "$add_output"
		return 1
	fi

	echo "✅ Worktree created successfully."
	echo "📦 Repo: $(git -C "$repo_path" remote get-url origin 2>/dev/null)"
	echo "🌿 Branch: $branch_name"
	echo "🌳 Worktree: $target_path"
	echo "🔖 Change: $change_num"
	echo "📍 HEAD:"
	if ! git -C "$repo_path" --no-pager log -1 --decorate --oneline 2>/dev/null; then
		echo "❌ Warning: Failed to print HEAD commit."
	fi

	if ! cd "$target_path"; then
		echo "❌ Error: Worktree created but failed to switch to '$target_path'."
		return 1
	fi
}

# Prevent alias/function name collisions during shell reload.
unalias cdr cdw gwo gwa gwl gws gwr gbs gpush cocr 2>/dev/null

# Alias for checkout-gerrit-cr
alias cocr='checkout-gerrit-cr'
alias gwl='gws'
alias gwr='gws --remove'

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
		find "$repos_root" -mindepth 1 -maxdepth 1 -type d 2>/dev/null |
			sort |
			fzf --prompt="Repo > " --height=40% --reverse
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
	gws "$@"
}

# Worktree menu shortcut
#
# Usage: gwo
gwo() {
	gws "$@"
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
		find "$repos_root" -mindepth 1 -type d -name .git -prune 2>/dev/null |
			sed "s#^$repos_root/##" |
			sed 's#/.git$##' |
			sort
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
	local default_branch_name="${selected_branch##*/}"
	local local_branch_name

	local remote_url
	remote_url="$(git remote get-url "$selected_remote" 2>/dev/null)"
	local is_gerrit=0
	if [[ "$remote_url" == *nugerrit.ntnxdpro.com* ]]; then
		is_gerrit=1
	fi

	while true; do
		read "local_branch_name?Local branch name [$default_branch_name]: "
		[[ -z "$local_branch_name" ]] && local_branch_name="$default_branch_name"

		if ! git check-ref-format --branch "$local_branch_name" >/dev/null 2>&1; then
			echo "❌ Error: '$local_branch_name' is not a valid branch name."
			local_branch_name=""
			continue
		fi

		local -a checked_out_worktrees
		local worktree_line worktree_path
		checked_out_worktrees=()
		worktree_path=""
		while IFS= read -r worktree_line; do
			case "$worktree_line" in
			"worktree "*) worktree_path="${worktree_line#worktree }" ;;
			"branch refs/heads/$local_branch_name")
				checked_out_worktrees+=("$worktree_path")
				;;
			esac
		done < <(git worktree list --porcelain 2>/dev/null)

		if ((${#checked_out_worktrees[@]} > 0)); then
			echo "⚠️  Branch '$local_branch_name' is already checked out at:"
			printf '    %s\n' "${checked_out_worktrees[@]}"
			local_branch_name=""
			continue
		fi

		break
	done

	local worktree_name
	read "worktree_name?Worktree name (relative to $worktrees_root): "
	if [[ -z "$worktree_name" ]]; then
		echo "❌ Error: Worktree name is required."
		return 1
	fi

	if [[ "$worktree_name" == */* || "$worktree_name" == "." || "$worktree_name" == ".." ]]; then
		echo "❌ Error: Worktree name must be a single directory name."
		return 1
	fi

	if ! mkdir -p "$worktrees_root" 2>/dev/null; then
		echo "❌ Error: Failed to ensure worktrees directory '$worktrees_root'."
		return 1
	fi

	local target_path="$worktrees_root/$worktree_name"
	if [[ -e "$target_path" || -L "$target_path" ]]; then
		echo "❌ Error: Path '$target_path' already exists."
		return 1
	fi

	echo
	echo "Worktree configuration:"
	echo "  Repo:          $selected_repo_path"
	echo "  Base branch:   $selected_remote_branch"
	echo "  Local branch:  $local_branch_name"
	echo "  Worktree:      $target_path"
	local confirmation
	read "confirmation?Create this worktree? [y/N]: "
	if [[ ! "$confirmation" =~ '^[Yy]$' ]]; then
		echo "❌ Cancelled."
		return 1
	fi

	echo "🔄 Fetching latest for '$selected_remote_branch'..."
	if ! git fetch "$selected_remote" "$selected_branch" 2>&1; then
		echo "❌ Error: Failed to fetch '$selected_remote_branch'."
		return 1
	fi

	if ! git show-ref --verify --quiet "refs/remotes/$selected_remote_branch"; then
		echo "❌ Error: Remote branch ref 'refs/remotes/$selected_remote_branch' does not exist after fetch."
		return 1
	fi

	local add_output
	if git show-ref --verify --quiet "refs/heads/$local_branch_name"; then
		echo "🌳 Reusing existing local branch '$local_branch_name' for worktree..."
		if ! add_output="$(git worktree add "$target_path" "$local_branch_name" 2>&1)"; then
			echo "❌ Error: Failed to create worktree."
			echo "$add_output"
			return 1
		fi
	elif ((is_gerrit)); then
		echo "🌳 Creating branch '$local_branch_name' and worktree from '$selected_remote_branch' (Gerrit - no tracking)..."
		if ! add_output="$(git worktree add -b "$local_branch_name" "$target_path" "$selected_remote_branch" 2>&1)"; then
			echo "❌ Error: Failed to create worktree."
			echo "$add_output"
			return 1
		fi
	else
		echo "🌳 Creating branch '$local_branch_name' and worktree from '$selected_remote_branch'..."
		if ! add_output="$(git worktree add --track -b "$local_branch_name" "$target_path" "$selected_remote_branch" 2>&1)"; then
			echo "❌ Error: Failed to create worktree."
			echo "$add_output"
			return 1
		fi
	fi

	if ! cd "$target_path"; then
		echo "❌ Error: Worktree created but failed to switch to '$target_path'."
		return 1
	fi

	link-agent-files

	echo "✅ Worktree created successfully."
	echo "📦 Repo: $selected_repo_path"
	echo "🌿 Branch: $selected_remote_branch"
	echo "🌳 Worktree: $target_path"
	if ((is_gerrit)); then
		echo "📍 Local branch: $local_branch_name (not publishing - gerrit remote)"
	else
		echo "📍 Local branch: $local_branch_name (tracking: $selected_remote_branch)"
	fi
	echo "📍 HEAD:"
	if ! git --no-pager log -1 --decorate --oneline; then
		echo "❌ Error: Failed to print HEAD commit."
		return 1
	fi
}

# Select a worktree to switch to, list, or remove
#
# Usage: gws | gwl | gwr
gws() {
	set +x 2>/dev/null
	emulate -L zsh
	local mode="switch"
	case "$1" in
	--list) mode="list" ;;
	--remove) mode="remove" ;;
	esac
	setopt localoptions noxtrace
	functions +t gws 2>/dev/null

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

	if ((${#worktrees[@]} == 0)); then
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

	if ((${#rows[@]} == 0)); then
		echo "❌ Error: Unable to read worktree metadata under '$active_worktrees_root'."
		return 1
	fi

	local -a sorted_rows
	sorted_rows=("${(@On)rows}")

	local limit=20
	if ((${#sorted_rows[@]} < limit)); then
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

			local local_branch
			local_branch="$(git -C "$wt_path" branch --show-current 2>/dev/null)"
			if [[ -n "$local_branch" ]]; then
				branch_display="$local_branch"
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

	local name_col=26
	local repo_col=16
	local branch_col=26
	local sep=$'\x1f'

	local repo_name
	for repo_name in "${repos[@]}"; do
		if ((${#repo_name} > repo_col)); then
			repo_col=${#repo_name}
		fi
	done
	((repo_col > 32)) && repo_col=32

	local -a menu_lines
	local header
	header="$(printf "%-${name_col}s  %-${repo_col}s  %-${branch_col}s  %s" \
		"WORKTREE" "REPO" "LOCAL BRANCH" "LAST MODIFIED")"
	menu_lines=("${header}${sep}__HEADER__")

	local name_view repo_view branch_view display_line
	for ((i = 1; i <= ${#names[@]}; i++)); do
		name_view="${names[$i]}"
		repo_view="${repos[$i]}"
		branch_view="${branches[$i]}"

		if ((${#name_view} > name_col)); then
			name_view="${name_view[1,$((name_col - 1))]}…"
		fi
		if ((${#repo_view} > repo_col)); then
			repo_view="${repo_view[1,$((repo_col - 1))]}…"
		fi
		if ((${#branch_view} > branch_col)); then
			branch_view="${branch_view[1,$((branch_col - 1))]}…"
		fi

		display_line="$(printf "%-${name_col}s  %-${repo_col}s  %-${branch_col}s  %s" \
			"$name_view" "$repo_view" "$branch_view" "${times[$i]}")"
		menu_lines+=("${display_line}${sep}${paths[$i]}")
	done

	if [[ "$mode" == "list" ]]; then
		printf "%s\n" "${menu_lines[@]%%$sep*}"
		return 0
	fi

	if ! command -v fzf >/dev/null 2>&1; then
		echo "❌ Error: 'fzf' is required to choose a worktree from the menu."
		return 1
	fi

	local fzf_prompt="Select worktree > "
	[[ "$mode" == "remove" ]] && fzf_prompt="Remove worktree > "

	local selected_line selected_path
	selected_line="$(
		printf "%s\n" "${menu_lines[@]}" |
			fzf \
				--prompt="$fzf_prompt" \
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
	if [[ "$mode" == "remove" ]]; then
		local confirmation=""
		read "confirmation?Remove worktree '$selected_path'? [y/N]: "
		if [[ ! "$confirmation" =~ '^[Yy]$' ]]; then
			echo "❌ Cancelled."
			return 1
		fi
		local remove_err
		if ! remove_err="$(git -C "$selected_path" worktree remove "$selected_path" 2>&1)"; then
			# Git refuses to remove worktrees containing submodules, even though
			# they can be force-removed. Only force if nothing is uncommitted.
			if [[ "$remove_err" == *"containing submodules"* ]]; then
				echo "⚠️  Worktree contains submodules; verifying it is clean before forcing removal..."
				if [[ -n "$(git -C "$selected_path" status --porcelain -uno 2>/dev/null)" ]] ||
					[[ -n "$(git -C "$selected_path" submodule foreach --quiet --recursive 'git status --porcelain -uno' 2>/dev/null)" ]]; then
					echo "❌ Worktree or its submodules have uncommitted changes; not removing."
					return 1
				fi
				git -C "$selected_path" worktree remove --force "$selected_path"
				return $?
			fi
			print -r -- "$remove_err" >&2
			return 1
		fi
		return 0
	fi

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

# Push to remote: handles both GitHub and Gerrit remotes.
#   - GitHub: standard git push
#   - Gerrit: push to magic ref refs/for/<branch> to create a CR
#
# Usage:
#   gpush                           # Push current branch to matching remote branch
#   gpush <remote-branch>           # Push current branch to a specific remote branch
#
# Examples:
#   gpush                            # Push current local branch
#   gpush origin/master              # Push current branch to origin/master
gpush() {
	local target_branch=""

	while (($# > 0)); do
		case "$1" in
		--help | -h)
			echo "Usage: gpush [remote-branch]"
			return 1
			;;
		*)
			if [[ -z "$target_branch" ]]; then
				target_branch="$1"
			else
				echo "❌ Error: Unexpected argument '$1'"
				return 1
			fi
			shift
			;;
		esac
	done

	local current_branch
	current_branch="$(git symbolic-ref --short HEAD 2>/dev/null)"
	if [[ -z "$current_branch" ]]; then
		echo "❌ Error: Not on a local branch (detached HEAD)."
		return 1
	fi

	if [[ -z "$target_branch" ]]; then
		target_branch="$current_branch"
	fi

	local remote_branch_name
	if [[ "$target_branch" == */* ]]; then
		remote_branch_name="${target_branch#*/}"
	else
		remote_branch_name="$target_branch"
	fi

	local remote_url
	remote_url="$(git remote get-url origin 2>/dev/null)"
	if [[ -z "$remote_url" ]]; then
		echo "❌ Error: No remote 'origin' configured."
		return 1
	fi

	echo "🔄 Pushing branch '$current_branch'..."
	local push_output
	if [[ "$remote_url" == *nugerrit.ntnxdpro.com* ]]; then
		local gerrit_ref="refs/for/$remote_branch_name"
		echo "   Gerrit remote detected - pushing to '$gerrit_ref'"
		if ! push_output="$(git push origin "$current_branch:$gerrit_ref" 2>&1)"; then
			echo "❌ Error: Gerrit push failed."
			echo "$push_output"
			return 1
		fi
	else
		if ! push_output="$(git push origin "$current_branch:$target_branch" 2>&1)"; then
			echo "❌ Error: Push failed."
			echo "$push_output"
			return 1
		fi
	fi

	echo "✅ Push completed."
	echo "$push_output"
}
