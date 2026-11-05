# Agent skills (vendored / synced)

The skill folders under [`skills/`](./skills/) are **not authored here**. They
are vendored copies **synced from upstream repositories** by the
[`skills` CLI](https://www.npmjs.com/package/skills) (`npx skills`). This
directory is tracked in the personal dotfiles repo so the same set of skills
follows me to every machine.

## Source of truth: `.skill-lock.json`

[`.skill-lock.json`](./.skill-lock.json) is the manifest. For every installed
skill it records the upstream repo, the path within that repo, and the pinned
commit hash. If you want to know where a skill came from, look there — don't
guess from the folder name.

**Exception:** `personal-dotfiles` and `upkeep` are authored directly in this
repo (they are not in `.skill-lock.json`). Edit them here.

Some upstreams are my own repos (e.g. `kevmoo/kevmoo_skills`,
`kevmoo/dash_skills`); most are not (`flutter/skills`, `dart-lang/skills`, …).

## Manage skills with the tool — never by hand

Use the `skills` CLI as usual to list, add, update, check, or remove skills:

```bash
npx skills            # list / help
upkeep check skills   # what's out of date (read-only)
npx skills update -g  # pull upstream updates
```

`npx skills check` is an alias of `update` and can install skills, so don't use
it as a probe.

> [!WARNING]
>
> **Do not hand-edit anything under `skills/`.** Those files are managed copies
> and will be **overwritten on the next sync**. To change a skill, edit its
> **upstream** repo (see `.skill-lock.json` for the source), then re-sync.

## The one manual step: commit & push into dotfiles

`npx skills` only changes files locally. Any add/update/remove touches the
`skills/` tree and `.skill-lock.json` — and **none of it reaches my other
machines until it's committed and pushed into the dotfiles repo.** So after any
skills change:

```bash
dot switch -c sync-skills
dot status -u ~/.agents            # inspect modified, deleted, and new files
dot add ~/.agents                  # stage all changes in allowlisted skills
dot commit -m "Sync global skills"
dot push -u origin sync-skills
```

`dot` (`~/.local/bin/dot`) wraps
`git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME`. Because
`status.showUntrackedFiles` is `no`, pass `-u` (`dot status -u ~/.agents`) to
see newly added files (e.g. `references/*.md`). Plain `dot add ~/.agents`
stages modified, deleted, and new files inside skills allowlisted in
`.config/dot/info-exclude.example` while ignoring `.DS_Store`, local `dash-okf*`
symlinks, and corp-only skills.

When adding a **brand-new** public skill, add `!.agents/skills/<name>/` and
`!.agents/skills/<name>/**` to `.config/dot/info-exclude.example` (and copy it
to `~/.dotfiles/info/exclude`), then stage both with `dot add`. Avoid
`dot add -f ~/.agents/skills` on the whole directory, which bypasses
`info/exclude`.

`upkeep check` will surface pending skill updates as `needsTriage` without
dirtying `.agents/` during routine `upkeep update` runs, and explicit
`upkeep update skills` runs the upstream sync for you — then commit/PR the
changes into `personal_dotfiles`.
