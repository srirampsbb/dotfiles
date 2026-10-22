---
name: circleci
description: Use for CircleCI CI/CD tasks - querying pipelines, projects, workflows, jobs, and validating config
compatibility:
  opencode: ">=1.0.0"
---

# CircleCI Skill

## Purpose

When working with CircleCI CI/CD tasks, use this skill to ensure proper authentication, query pipeline/project/workflow/job information, monitor job status, and validate CircleCI config files.

## Authentication (fail-early)

Always validate authentication before proceeding:

```bash
/usr/local/bin/circleci info org
```

If this fails (e.g., "please set a token"), stop and ask the user to fix auth. do NOT proceed any further.

## Workflow

### 1. Parse CircleCI URLs

When given a CircleCI URL, derive project, workflow, and job details from it. From the example URL:

```
https://app.circleci4.corp.p10y.ntnxdpro.com/pipelines/github/nutanix-core/nc2-igw-cli/2437/workflows/4844fca8-af51-4274-989e-73f8eba24026
```

Parse out:

- vcs-type: `github`
- org-slug: `nutanix-core`
- project name: `nc2-igw-cli`
- pipeline number: `2437`
- workflow-id: `4844fca8-af51-4274-989e-73f8eba24026`

### 2. Query Organization Info

```bash
/usr/local/bin/circleci info org --json
```

### 3. Query Pipelines

```bash
/usr/local/bin/circleci pipeline list <project-id>
```

### 4. Monitor Jobs

Monitor **all jobs** within a workflow by providing a CircleCI workflow URL:

```bash
/usr/local/bin/circleci info org  # validate auth first
cci_monitor_all_jobs <circleci-workflow-url>
```

This runs the helper function defined in `/home/sriram.ravichandran/.dotfiles/zsh/local/ntnx-cci.zsh`. If this command fails or the function is not available, check:

1. The script exists at `/home/sriram.ravichandran/.dotfiles/zsh/local/ntnx-cci.zsh`
2. Your shell has been reloaded (`src` or `exec zsh`)
3. `CIRCLECI_CLI_TOKEN` is exported in your environment

The script does:

1. Extracts the workflow-id from the URL
2. Fetches all jobs under the workflow via `/api/v2/workflow/<id>/job`
3. Prints each job name and its status
4. Polls every 30s (up to 120 attempts) until all jobs reach terminal states (`success`, `failed`, `canceled`, etc.)
5. Prints errors clearly if the API call fails, returns non-200, or times out

Ensure `CIRCLECI_CLI_TOKEN` is exported (set in `zsh/local/ntnx-env.zsh`) before running.

## Config Validation

When `.circleci/config.yml` is modified in the current git branch, validate it:

```bash
/usr/local/bin/circleci config validate .circleci/config.yml
```

To validate and display the expanded configuration:

```bash
/usr/local/bin/circleci config process .circleci/config.yml
```

## Notes

- Global flags available on all commands: `--host`, `--token`, `--skip-update-check`
- The host default is `https://circleci4.corp.p10y.ntnxdpro.com` (private Nutanix instance)
- There is no dedicated CLI subcommand for job status monitoring; use the API with curl
- Do NOT create pipelines — use existing pipelines for querying and monitoring
