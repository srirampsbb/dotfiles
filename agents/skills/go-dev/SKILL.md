---
name: go-dev
description: Use for Go development tasks - coding, linting, LSP integration, and error fixing
compatibility:
  opencode: ">=1.0.0"
---

# Go Development Skill

## Purpose

When working with Go files (.go), use this skill to ensure proper coding, linting, LSP diagnostics handling, and error resolution.

## Workflow

### 1. coding guidelines

- First, understand the package structure in the repo and the functionality of each package
- When creating new functions, consider grouping them into packages where applicable. Then either fit them into existing packages or create new packages as needed
- Where appripriate, define interfaces
- Use mockery to generate mocks for interfaces as well as external packages to the extent possible
- Write unit tests that achieve code coverage of at least 85%

### 2. Linting

After writing files, run `golangci-lint run` on changed packages:

```
golangci-lint run <package-path>
```

Analyze output and fix all reported errors. warnings can be skipped but list them and explain why.
If any error needs to touch more than 3 files, pause and ask for confirmation before proceeding.

### 3. Build Verification

Run `go build ./...` and `go vet ./...` to catch compilation errors and static issues.

### 4. LSP Integration

If LSP is enabled (`gopls`):

- Review diagnostic warnings/errors after writes
- Apply quick fixes suggested by `gopls`

### 5. Dependency Management

After modifying imports, run `go mod tidy` and verify dependencies with `go mod verify`.

## Notes

- Use `go version` to verify Go installation
- Include proper Go module documentation in comments
