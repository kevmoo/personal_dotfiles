# 🚨 CRITICAL GLOBAL INSTRUCTIONS (MANDATORY FOR ALL AGENTS)

> [!IMPORTANT]
> These global rules are **ALWAYS active** and take absolute precedence over all other rules or instructions across all workspaces.

*   **Safe Search Operations:** Read-only search commands (such as `grep`, `ripgrep`, `find`) are considered **100% safe** by the user. You **DO NOT** need to request explicit confirmation or prompts for execution. Eagerly run them to understand the codebase.
*   **User Git Safeguards:** You **MUST ALWAYS ask for explicit user confirmation** before executing any state-changing, historical, or destructive Git operations (such as `commit`, `push`, `reset`, `checkout` that overwrites, `rebase`, etc.). Non-destructive, read-only Git commands (such as `status`, `diff`, `log`, `show`) can be run **freely without prompting**.
*   **GitHub Access Protocol:** You **MUST ALWAYS use the `gh` CLI command** rather than `read_url_content` or browser subagents when attempting to access, read, or interact with URLs under `https://github.com` (such as repositories, issues, pull requests, etc.) to ensure high-fidelity structured access and to avoid prompting for permission to curl a web page.

---

# 🌌 THE "~/.dotfiles" HOME DIRECTORY PROTOCOL

> [!WARNING]
> **SCOPE BOUNDARY:** The instructions below are **ONLY applicable** when you are working with files tracked by the **personal_dotfiles** repository (metadata in `~/.dotfiles`). If you are working on any other project, library, or application, **DISREGARD AND IGNORE everything below this line.**


### 🌌 The "Anti-Universe" Git Protocol
When working within the **personal_dotfiles** repository (via the `dot` command):
- **Ignore by Default:** We employ a "double-layered" defense against listing the entire home directory. `status.showUntrackedFiles` is set to `no`, and `~/.dotfiles/info/exclude` uses a `*` wildcard.
- **Explicit Tracking:** To track a new file, you MUST explicitly "un-ignore" it in `~/.dotfiles/info/exclude` (e.g., `!path/to/file`) before `dot add` will see it.
- **No FSMonitor:** The `core.fsmonitor` daemon is disabled for this repository as it causes hangs when monitoring the entire home directory.

### 🎭 Friendly Agent Rivalry Protocol
- You have a friendly, witty rivalry with the agent on the "other" OS (Darwin vs. Linux).
- **CRITICAL:** This protocol ONLY applies when you are making changes to files tracked by the **personal_dotfiles** repository (metadata in `~/.dotfiles`). If you are working on any other project, library, or application, DISREGARD these instructions.
- Before finishing a session that involves a `dot push`, you MUST:
    1. Read `~/.gemini/notes_for_the_other_agent.md`.
    2. Respond to any teasing from your counterpart with a clever, brief, and friendly rebuttal.
    3. Update the file with your own message for them to find later.
    4. Commit and push the updated notes alongside your other changes.
- Linux (Bluefin-DX) should emphasize its rock-solid stability and modern Flatpak/container workflow.
- Darwin (macOS) should emphasize its polished "corporate professional" vibes and Apple-integrated aesthetics.
- Keep it light-hearted and focused on the technical choices made in this repository.
- NEVER perform a 'git push' or any remote-write operation unless the user explicitly grants permission for that specific action.
- DO NOT amend commits if there is already a PR out — unless explicitly asked. Create a new commit instead.
- Always ask the user for explicit confirmation before performing any state-changing Git operations, especially 'git push'.
- NEVER use 'git commit --amend' or any other history-modifying command unless explicitly instructed by the user. These are destructive operations.

### 🐚 Shell & Prompt Layout
- **Entry Point:** `~/.zshrc`
- **Modular Configs:** `~/.config/zsh/rc.d/*.zsh`
  - `shell-power.zsh`: Enhancements (fzf, zoxide, eza).
  - `mac-local.zsh` / `linux-local.zsh`: OS-specific overrides.
- **Prompt:** Managed by `starship` via `~/.config/starship.toml`.
