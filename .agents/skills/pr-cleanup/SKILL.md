---
name: pr-cleanup
description: >-
  Orchestrates multi-repo GitHub pull request, Gerrit CL, local Git worktree,
  and branch cleanup sweeps alongside active open-PR next-step triage. Use when
  asked to run a PR cleanup sweep, prune merged worktrees or branches, review
  open PRs and next steps across repositories, or reconcile local checkouts in
  ~/github against GitHub, Gerrit, and active agent sessions. Don't use for
  triaging inline review comments or CI failures on a single PR (use pr-triage)
  or creating new worktrees (use new-worktree).
compatibility: "Requires kscripts (kevmoo_scripts via dart install) and local checkouts in ~/github"
metadata:
  author: kevmoo
  target_environment: personal
---

# PR & Worktree Cleanup Sweep (`pr-cleanup`)

> [!NOTE]
>
> This skill invokes the unified `kscripts pr-cleanup` CLI to inspect and prune
> worktrees, branches, and PRs/CLs across `~/github` and Gerrit in parallel.

## 1. Quick Start & Prerequisites

Ensure `kscripts` is installed and current:

```bash
which kscripts || dart install 'kevmoo_scripts@{git: https://github.com/kevmoo/scripts.dart}'
```

## 2. Phase 1 — Read-Only Unified Sweep (Always Start Read-Only)

Never pass `--apply` on the initial turn. Run the unified collector:

```bash
kscripts pr-cleanup --markdown
```

_(Pass `--json` when machine parsing is preferred, or `-R <owner/repo>` to scope to specific repositories)._

The unified collector queries GitHub landed PRs, active open PRs, local Git checkouts, and Gerrit Dart SDK CLs concurrently, categorizing everything into three deterministic buckets:

- **Bucket A — Active / In-Flight (`🚫 Hands-Off`)**: Open PRs and active Gerrit CLs with CI and reviewer status badges, along with mapped local worktrees.
- **Bucket B — Safe to Prune Immediately (`✅ Ready`)**: Landed PRs and merged Gerrit CLs with clean worktrees, deleted remote branches, and merged local branches.
- **Bucket C — Requires Explicit Confirmation (`⚠️ Review First`)**: Worktrees with uncommitted/dirty changes, unpushed commits ahead of trunk, or closed-unmerged PRs.

## 3. Phase 2 — Present Findings & Approval Gate

Present the Markdown report in chat. If Bucket B contains items to prune, prompt the user via `ask_question`:

- `(Recommended) Execute Bucket B only (prune merged PRs, clean worktrees & remote branches)`
- `Execute Bucket B + approved Bucket C items`
- `Stop here (keep read-only report only)`

## 4. Phase 3 — Execution

1. **Execute Bucket B Pruning**:

   ```bash
   kscripts pr-cleanup --apply
   ```

   This atomically removes clean worktrees and deletes merged branches across both GitHub and Gerrit checkouts.

2. **Execute Approved Bucket C Items** _(only if user explicitly instructed)_:

   ```bash
   git -C <repo_path> worktree remove --force <worktree_path>
   git -C <repo_path> branch -D <branch>
   ```

3. **Reconcile Tasks & Sister Sessions**:
   - Check the **Landed PR/CL IDs** section in the sweep output.
   - For any matching open PM-OS or Wynette tasks, follow [pr-cleanup-pm-os-reconciliation.md](topics/pr-cleanup-pm-os-reconciliation.md) to close completed tasks or update waiting agent conversations.
