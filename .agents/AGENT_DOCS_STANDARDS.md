# Agentic Documentation & Skill Standards

Authoritative standards for authoring and maintaining `SKILL.md`, `AGENTS.md`,
`CLAUDE.md`, `GEMINI.md`, and skill `references/*.md` files.

## 1. Line-Budget Ceilings & Progressive Disclosure ("Cognitive Complexity for Prompts")

- **`SKILL.md` (`50–250` lines target, `<= 350` lines hard ceiling)**: Keep
  `SKILL.md` as the lean execution spine (`## Quick Start`, numbered workflow
  phases, and decision gates). Offload JSON/YAML schemas, GraphQL queries, long
  lookup tables, and copy-paste templates into `references/<topic>.md` (`<= 300`
  lines per file) loaded on demand.
- **Always-On Instruction Files (`AGENTS.md`, `CLAUDE.md`, `GEMINI.md` `<= 200`
  lines)**: Every line in an always-on instruction file taxes every turn of
  every session. Offload one-time workstation onboarding, detailed workflow
  playbooks, and reference tables into `docs/<topic>.md`,
  `references/<topic>.md`, or `.agents/skills/<name>/SKILL.md`, linking each
  from `AGENTS.md` with a 1-line conditional read cue (for example:
  `For macOS onboarding, read [docs/mac_setup.md](docs/mac_setup.md)`).
- **Zero Content Loss on Extraction (The `shallow` Equivalent)**: Never lower a
  `SKILL.md` or `AGENTS.md` line count by silently deleting CLI flags,
  edge-case guards, verification commands, or decision branches. Tightening
  wordy prose in-place is encouraged, provided all commands, flags, thresholds,
  and branches remain intact either inline or in a linked `docs/` /
  `references/` file.

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
