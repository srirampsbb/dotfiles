#!/usr/bin/env zsh
# Verifies formatters/linters on changed files in the workspace.
# Each required executable is checked before use; if missing, an explicit error
# is logged and the affected check is skipped.
#
# Only ONES found in PATH are run. Missing tools are reported in a summary at
# the end so the LM can install them or follow up.
#
# Usage:
#   code-checker.zsh [--all] [file ...]
#
#   --all      Check every file tracked by git in the repository.
#   file ...   Check only the given files. Relative paths are resolved against
#              the directory the script was invoked from.
#
# With no arguments, staged, unstaged, and untracked files are checked.

# zsh does not word-split unquoted variables by default; enable it so the
# per-language file lists below expand into separate arguments.
setopt shwordsplit

# Parse arguments: an optional --all flag and/or an explicit list of files.
CHECK_ALL=0
typeset -a INPUT_FILES
for arg in "$@"; do
	case "$arg" in
	--all) CHECK_ALL=1 ;;
	*) INPUT_FILES+=("${arg:A}") ;;
	esac
done

# Work from the repository root so git output and the file lists line up.
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$REPO_ROOT" ]; then
	echo "!! ERROR: not inside a git repository."
	exit 1
fi
cd "$REPO_ROOT" || exit 1

# Pass through only regular files that exist on disk, one per line.
filter_existing() {
	while IFS= read -r f; do
		[ -n "$f" ] && [ -f "$f" ] && print -r -- "$f"
	done
}

if [ "$CHECK_ALL" -eq 1 ]; then
	# Every file tracked by git.
	CHANGED_FILES=$(git ls-files | filter_existing)
elif [ ${#INPUT_FILES[@]} -gt 0 ]; then
	# Explicit file list (resolved to absolute paths above).
	CHANGED_FILES=$(print -rl -- "${INPUT_FILES[@]}" | filter_existing)
else
	# Get staged, unstaged, and untracked files (excluding deleted files).
	# -uall lists each untracked file individually instead of collapsing
	# untracked directories into a single entry, so nested new files are checked.
	CHANGED_FILES=$(git status --porcelain -uall | awk '$1 !~ /^D/ {print $2}' | filter_existing)
fi

if [ -z "$CHANGED_FILES" ]; then
	echo "No files to check."
	exit 0
fi

echo "Checking files:"
echo "$CHANGED_FILES"
echo "----------------------------------------"

PYTHON_FILES=$(echo "$CHANGED_FILES" | grep -E '\.py$' || true)
GO_FILES=$(echo "$CHANGED_FILES" | grep -E '\.go$' || true)
SH_FILES=$(echo "$CHANGED_FILES" | grep -E '\.sh$' || true)
ZSH_FILES=$(echo "$CHANGED_FILES" | grep -E '\.zsh$' || true)
LUA_FILES=$(echo "$CHANGED_FILES" | grep -E '\.lua$' || true)
JSON_FILES=$(echo "$CHANGED_FILES" | grep -E '\.jsonc?$' || true)
YAML_FILES=$(echo "$CHANGED_FILES" | grep -E '\.ya?ml$' || true)
MD_FILES=$(echo "$CHANGED_FILES" | grep -E '\.mdx?$' || true)

# Tracks executables that were required but not found in PATH.
MISSING_TOOLS=""

# Verify an executable exists before invoking it. On failure, log an explicit
# error, record the tool, and return non-zero so the caller can skip it.
require_tool() {
	tool="$1"
	purpose="$2"
	if command -v "$tool" >/dev/null 2>&1; then
		return 0
	fi
	echo "!! ERROR: required tool '$tool' not found in PATH -- skipping $purpose."
	MISSING_TOOLS="$MISSING_TOOLS $tool"
	return 1
}

# Python Checks (Auto-fix basic issues, report remaining)
if [ -n "$PYTHON_FILES" ]; then
	echo "==> Python Checks"
	if require_tool uvx "ruff formatting and linting via uvx"; then
		uvx ruff format $PYTHON_FILES
		uvx ruff check --fix --show-fixes $PYTHON_FILES || true
	fi
	if require_tool basedpyright "Python type checking"; then
		basedpyright $PYTHON_FILES || true
	fi
fi

# Go Checks
if [ -n "$GO_FILES" ]; then
	echo "==> Go Checks"
	if require_tool gofmt "Go formatting"; then
		gofmt -w $GO_FILES
	fi
	if require_tool golangci-lint "Go linting"; then
		golangci-lint run --fix $GO_FILES || true
	fi
fi

# Shell Checks (sh/bash) -- formatted with shfmt.
if [ -n "$SH_FILES" ]; then
	echo "==> Shell Checks"
	if require_tool shfmt "sh/bash formatting"; then
		shfmt -ln=bash -w $SH_FILES || true
	fi
fi

# Zsh Checks -- use shfmt (format) + zsh -n (syntax).
if [ -n "$ZSH_FILES" ]; then
	echo "==> Zsh Checks"
	if require_tool shfmt "zsh formatting"; then
		shfmt -ln=zsh -w $ZSH_FILES || true
	fi
	# zsh -n only checks its first argument, so loop per file.
	for zf in $ZSH_FILES; do
		zsh -n "$zf" || true
	done
fi

# Lua Checks -- format with stylua, then lint with lua-language-server.
if [ -n "$LUA_FILES" ]; then
	echo "==> Lua Checks"
	if require_tool stylua "Lua formatting"; then
		stylua $LUA_FILES || true
	fi
	if require_tool lua-language-server "Lua checks"; then
		lua-language-server --check $LUA_FILES --checklevel=Warning || true
	fi
fi

# Prettier Checks -- format JSON, YAML, and Markdown files.
if [ -n "$JSON_FILES$YAML_FILES$MD_FILES" ]; then
	echo "==> Prettier Checks"
	if require_tool prettier "JSON/YAML/Markdown formatting"; then
		prettier --write $JSON_FILES $YAML_FILES $MD_FILES || true
	fi
fi

if [ -n "$MISSING_TOOLS" ]; then
	echo "----------------------------------------"
	echo "!! MISSING TOOLS: the following executables were not found and their checks were skipped:$MISSING_TOOLS"
fi
