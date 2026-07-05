# Agent skills (vendored / synced)

The skill folders under [`skills/`](./skills/) are **not authored here**. They
are vendored copies **synced from upstream repositories** by the [`skills`
CLI](https://www.npmjs.com/package/skills) (`npx skills`). This directory is
tracked in the personal dotfiles repo so the same set of skills follows me to
every machine.

## Source of truth: `.skill-lock.json`

[`.skill-lock.json`](./.skill-lock.json) is the manifest. For every installed
skill it records the upstream repo, the path within that repo, and the pinned
commit hash. If you want to know where a skill came from, look there — don't
guess from the folder name.

Some upstreams are my own repos (e.g. `kevmoo/kevmoo_skills`,
`kevmoo/dash_skills`); most are not (`flutter/skills`, `dart-lang/skills`, …).

## Manage skills with the tool — never by hand

Use the `skills` CLI as usual to list, add, update, check, or remove skills:

```bash
npx skills            # list / help
npx skills check      # what's out of date
npx skills update -g  # pull upstream updates
```

> [!WARNING]
> **Do not hand-edit anything under `skills/`.** Those files are managed copies
> and will be **overwritten on the next sync**. To change a skill, edit its
> **upstream** repo (see `.skill-lock.json` for the source), then re-sync.

## The one manual step: commit & push into dotfiles

`npx skills` only changes files locally. Any add/update/remove touches the
`skills/` tree and `.skill-lock.json` — and **none of it reaches my other
machines until it's committed and pushed into the dotfiles repo.** So after any
skills change:

```bash
dot add -f ~/.agents/.skill-lock.json ~/.agents/skills
dot commit -m "skills: sync"
dot push
```

`dot` is the dotfiles alias: `git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME`
(the `-f` is required because `$HOME` is ignored-by-default under the
"Anti-Universe" bare-repo setup).

`upkeep check` will surface pending skill updates, and `upkeep update` runs the
sync for you — but the commit/push above is still the step to remember.
