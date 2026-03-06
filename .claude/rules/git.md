# Git Workflow Rules

## Branch Management

- **Always work in branches** off the latest `main`. Never commit directly to `main`.
- **Branch naming:** Alphanumeric with hyphens allowed (e.g., `add-git-rules`, `fix-caddy-config`). No slashes.

## Git Commands

- **Write operations** (commit, push, rebase, merge): Always run **unsandboxed** (with `dangerouslyDisableSandbox: true`).
- **Read operations** (status, log, diff): Safe to run in sandbox.
- If you need to commit to external repos (e.g., homelab-config), use the `-C` flag, e.g., `git -C ~/src/homelab-config/ commit`. Don't use `cd ... && git ...`.

## Commit/PR Descriptions

- **Always write commit messages and PR descriptions to `.tmp/commit-[random_string].txt` or `.tmp/pr-[random_string].md` using your Write() tool**
  — Never use `cat`, heredoc, or multi-line `-m` syntax
- `git commit -F .tmp/commit-123abc.txt`
- `gh pr create -t "My Pull Request" -F .tmp/pr-123abc.md`

## GitHub Integration

- Use `gh` CLI for PR, issue, and check operations when appropriate.
- **Always run `gh` outside the sandbox** (unsandboxed).

## Merging PRs

- **Before merging:** Verify all GitHub checks have passed.
- **Merge strategy: Always **squash merge** PRs and delete the PR branch (`gh pr merge --squash --delete-branch`)
  - **Never use merge commits.**
