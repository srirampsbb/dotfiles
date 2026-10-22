# Agent Instructions

## Output Style

- Keep all explanations and responses concise and direct. Avoid unnecessary preamble.

## Post-Edit Workflow

- when you are done modifying all files for the current task, run:
  ```bash
  $HOME/.local/bin/lint
  ```
- process the output and fix any linter errors until the script says something like "Done: all checks completed"
