---
description: Run formatters/linters on changed files, then apply suggested fixes and resolve diagnostic errors
---

Execute the following verification script on changed files in the workspace:

!`cd "$(git rev-parse --show-toplevel)" && zsh "$HOME/.config/opencode/commands/code-checker.zsh" $ARGUMENTS`

### Instruction for Agent:

Review the linter and compiler diagnostic output above carefully:

1. **Auto-fixes applied:** Notice any changes made directly by `--fix` flags (`uvx ruff check`, `gofmt`, `golangci-lint`, `shfmt`, or `stylua`).
2. **Remaining errors:** For any unresolved errors or type-check failures reported by `basedpyright`, `golangci-lint`, `zsh -n`, or `lua-language-server`:
   - Locate the exact files and lines flagged.
   - Edit the code directly to implement the linter's suggestions and resolve the errors.
3. **Re-verify:** After editing, run `/code-checker` once more to ensure **0 diagnostics remain**.
