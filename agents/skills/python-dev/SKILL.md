---
name: python-dev
description: Use for Python development tasks - coding, linting, LSP integration, and error fixing
compatibility:
  opencode: ">=1.0.0"
---

# Python Development Skill

## Coding guidelines

- add doc strings for all functions explaining input output and brief functionality.
- update functionality if needed
- for cli, provide example usages

## Workflow

### 1. Format and Lint

First make all changes and finally run format, lint and other tools. do NOT run them for each file.
before running tools, determine the Python environment:

- check if uv is installed `uv --version`. If so, use UV managed tools (`uv venv`, `uv run ruff`, etc.)
- if uv not installed, fall back to creating virtual env with `python -m venv` and using pip to install tools
- use `ruff format` to format and `ruff check` to lint.
- fix lint issues if they are straightforward. If a fix touches more than 5 files, ask for approval

### 2. LSP Integration Selection Strategy

use pyright for static analysis. install via uv or pip if not present
