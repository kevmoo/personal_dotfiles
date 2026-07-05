# ⚠️ These skills are vendored — do not hand-edit

Every folder here is a **synced copy** pulled from an upstream repo by the
`skills` CLI (`npx skills`). Editing these files directly is pointless: the
next sync **overwrites** them.

- To change a skill, edit its **upstream** repo. See `../.skill-lock.json` for
  each skill's source repo, path, and pinned commit.
- To add / update / remove skills, use `npx skills` — not manual file ops.
- After any change, **commit & push into the dotfiles repo** (`dot`), or it
  won't reach the other machines.

Full details: [`../README.md`](../README.md).
