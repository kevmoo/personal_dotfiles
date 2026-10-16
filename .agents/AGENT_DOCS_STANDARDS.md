# Agentic Documentation & Skill Standards

Authoritative standards for authoring and maintaining `SKILL.md`, `AGENTS.md`,
`CLAUDE.md`, `GEMINI.md`, and skill `references/*.md` files.

## 1. Character / Token Budgets & Progressive Disclosure ("Cognitive Complexity for Prompts")

- **`SKILL.md` (`<= 25,000` chars / `~6,250` tokens ceiling)**: Measure prompt
  size in characters (`~4 chars/token`) rather than physical line counts, which
  unfairly penalize `80`-column Prettier wrapping (`--prose-wrap always`), blank
  separator lines, and fenced CLI examples. Keep `SKILL.md` self-contained when
  within budget; only offload large JSON/YAML schemas, GraphQL queries, or long
  lookup tables into `references/<topic>.md` (`<= 20,000` chars per file) when a
  skill exceeds `25,000` characters or the reference material is rarely needed.
- **Always-On Instruction Files (`AGENTS.md`, `CLAUDE.md`, `GEMINI.md` `<=
15,000` chars / `~3,750` tokens)**: Every character in an always-on
  instruction file taxes every turn of every session. Offload one-time
  workstation onboarding, deep architecture guides, and optional playbooks into
  `docs/<topic>.md`, `references/<topic>.md`, or `.agents/skills/<name>/SKILL.md`,
  linking each from `AGENTS.md` with a 1-line conditional read cue (for example:
  `For macOS onboarding, read [docs/mac_setup.md](docs/mac_setup.md)`).
- **Zero Content Loss & No Safety-Critical Hop Splits**: Never lower a
  `SKILL.md` or `AGENTS.md` character count by silently deleting CLI flags,
  edge-case guards, verification commands, or decision branches. Do not extract
  core safety invariants or mandatory execution steps into `references/*.md`
  when a file is already within budget, as each `references/*.md` split adds a
  probabilistic `read_file` tool hop that agents may skip under context
  pressure.

## 2. Frontmatter & Trigger Contract (`SKILL.md` Only)

- **Scope (`**/SKILL.md` Only)**: These frontmatter rules apply strictly to
  agent skill manifests (`SKILL.md`), not to data/content frontmatter (such as
  OKF entries or blog posts).
- **Required Keys & Folded Scalar**: `name` must match the parent directory
  (`^[a-z0-9-]+$`). Use `description: >-` (`<= 1024` characters, with zero `<`
  or `>` angle brackets).
- **Trigger-Only `description:`**: Open with 1 third-person capability sentence
  stating what outcome the skill achieves (`Audits...`, `Orchestrates...`),
  followed by explicit `Use when ...` (positive triggers) and
  `Don't use for ...` / `Do not use for ...` (negative triggers naming
  alternative skills).
- **No Implementation Leakage in Frontmatter**: Never put backtick code spans,
  CLI flags (`--foo`), filesystem paths (`~/...`, `/google/...`), internal step
  sequences, or output templates inside `description:`. Plain-text trigger slash
  commands (`/skill-name`) and skill slugs (`use other-skill`) without backticks
  are allowed.

## 3. Anti-Bloat & Self-Edit Discipline (`lr_autonomous` + 3-Bucket Gate)

- **Script-Over-Prose Rule**: When a workflow step requires `> 15` lines of
  deterministic shell, git, jq, Python, or validation logic, implement it in
  `scripts/` or a CLI subcommand (`kscripts`) rather than instructing the LLM in
  prose or embedding `> 15`-line inline `python3 -c` / shell scripts inside
  markdown code fences.
- **3-Bucket Gate for Modifying Existing Docs (`lr_autonomous`)**:
  1. **Bucket 1 — Proven Blind-Spot Fix**: Adding new guardrail or checklist
     prose to an existing `SKILL.md` or `AGENTS.md` requires either (a)
     replacing/consolidating overlapping bullets in-place (`<= 0` net line
     delta), or (b) citing `>= 2` concrete historical failures/misses in the
     **Git commit message or PR description** (never as changelog noise inside
     `SKILL.md` or `AGENTS.md`).
  2. **Bucket 2 — Standalone New Capability**: Put genuinely new opt-in
     workflows, flags, or decision rubrics in a standalone skill, `scripts/*`,
     or an on-demand `docs/*.md` / `references/*.md` file so existing workflows
     pay zero always-on token tax.
  3. **Bucket 3 — Reject Speculative Prose**: Reject "just in case" reminders,
     polite restatements of existing rules (`[COVERED_LOCALLY]`), and unproven
     multi-pass checklists (`[UNPROVEN_PROSE]`).
- **One Domain = One Skill (Anti-Fragmentation)**: Prefer adding a subcommand or
  `references/<mode>.md` to an existing domain skill over spawning micro-skills
  (`< 50` lines) that compete for overlapping trigger phrases.

## 4. Markdown, Code Snippet & Reference Hygiene

- **No Unicode Dashes in Code**: Never put Unicode em-dashes (`—`, `U+2014`) or
  en-dashes (`–`, `U+2013`) anywhere inside executable fenced code blocks
  (`bash`, `sh`, `dart`, `python`, `json`, `yaml`, etc., including `# comment`
  lines inside code blocks) or as CLI flag prefixes inside inline backticks; use
  ASCII `--` or `-`.
- **No `[TOC]` & No Hardcoded `/tmp`**: Omit `[TOC]` and
  `<!-- mdformat ... -->` in GitHub Markdown (use Prettier-safe `> [!NOTE]`
  alerts with an empty `>` separator line). Avoid unguarded hardcoded `/tmp/...`
  paths in reusable scripts/commands (use `mktemp -d` or session-scoped
  directories).
- **Internal Markdown Link & Reference Integrity**: Every internal Markdown link
  across `.md` files must resolve to an existing file on disk (prefer paths
  relative to the source document over leading-slash `/...` links, and wrap
  illustrative placeholder links like `` `[Concept](/category/slug.md)` `` in
  inline code spans). Every file under a skill's `references/` directory must be
  linked from its `SKILL.md`.
- **Bundled Scripts (`scripts/*`)**: Include docstrings on all functions, keep
  helpers `<= 40` lines with descriptive variable names, and pair non-trivial
  scripts with unit tests covering normal, multi-branch, and fast-exit edge
  cases.

## 5. 3D Paranoia Tier Classification (`OQ3`)

<!-- SPOT_DEF: workflow-3d-paranoia-tiers -->

- **Banner Format**: Render at the top of review and PR draft preview artifacts
  (and in chat):
  `🛡️ Paranoia Tier: Ring <0..4B> (<Label>) · Confidence: <High|Low> · Door: <🚪 One-Way | 🔄 Two-Way>`
- **Reuse Ring (`Ring 0..4B`)**: `Ring 0` (personal dotfiles & private configs) ·
  `Ring 1-2` (public skills, utilities & internal scripts) · `Ring 3` (published
  `pub.dev` packages) · `Ring 4A` (upstream Dart/Flutter framework & packages) ·
  `Ring 4B` (upstream C++, Dart VM internals, WIMP, Skwasm engine). Default to
  `Review Mode: Standard` on `Ring 0-2` and `Review Mode: Deep` on `Ring 3-4` or
  when `--deep` (`--paranoid`) is passed.
- **Confidence (`High | Low`)**: `High` for familiar pure Dart, CLI, package &
  framework code; `Low` (forcing `Review Mode: Deep`) for unfamiliar C++, VM
  internals, or WIMP/Skwasm/engine plumbing.
- **Door Type (`🚪 One-Way | 🔄 Two-Way`)**: `🚪 One-Way` (forcing
  `Review Mode: Deep`) for public `api.txt` / CLI flag / JSON schema deltas,
  SemVer `-wip` bumps, DB migrations, or CI release workflows; `🔄 Two-Way` for
  internal `lib/src/` refactors, isolated tests, and docs.

<!-- END_SPOT_DEF: workflow-3d-paranoia-tiers -->
