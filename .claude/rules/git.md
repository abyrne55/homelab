# Git Workflow Rules

## Branch Management

- **Always work in branches** off the latest `main`. Never commit directly to `main`.
- **Branch naming:** Alphanumeric with hyphens allowed (e.g., `add-git-rules`, `fix-caddy-config`). No slashes.

## Git Commands

- **Write operations** (commit, push, rebase, merge): Always run **unsandboxed** (with `dangerouslyDisableSandbox: true`).
- **Read operations** (status, log, diff): Safe to run in sandbox.

## GitHub Integration

- Use `gh` CLI for PR, issue, and check operations when appropriate.
- **Always run `gh` outside the sandbox** (unsandboxed).

## Merging PRs

- **Before merging:** Verify all GitHub checks have passed.
- **Merge strategy:**
  - **Squash merge** for multi-commit PRs (default).
  - **Rebase merge** for small, single-commit PRs (e.g., version bumps, trivial fixes).
  - **Never use merge commits.**
