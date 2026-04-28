# Agent Guide for Dotfiles

This repository tracks dotfiles in the home directory (`$HOME`) using a bare git repository located at `~/.dotfiles/`. 

## How to Add New Files (The "Anti-Universe" Problem)

This repository uses a `*` wildcard in `~/.dotfiles/info/exclude` to ignore everything in `$HOME` by default. 

**The Gotcha:** Git's ignore logic has a strict rule: *It is not possible to re-include a file if a parent directory of that file is excluded.*

If you try to un-ignore a specific nested file (e.g., `!.config/git/hooks/script.sh`), but the parent `.config/` directory is ignored by the `*` rule, Git will never descend into `.config/` and your negative rule will never trigger. A standard `git add` will fail, claiming the file is ignored.

### Solution 1: Force Add (Recommended for deep paths)
The easiest and most reliable way to track a new file deeply nested in an ignored directory is to bypass the ignore list and force-add it directly to the index:
```bash
git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME add -f path/to/file
```
Once a file is tracked in the index, Git will continue to monitor it for modifications, even if it technically matches an ignore pattern.

### Solution 2: Explicitly Un-ignore All Parent Directories
If you prefer to maintain the `~/.dotfiles/info/exclude` file, you MUST un-ignore every single parent directory down to the file. For example:
```text
*
!.config/
!.config/git/
!.config/git/hooks/
!.config/git/hooks/*
```
*(Notice the trailing slashes—they are required to explicitly un-ignore the directories themselves so Git will descend into them.)*
