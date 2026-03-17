## Gemini Added Memories
- The user considers grep and similar read-only search commands (like ripgrep) to be safe and should not require explicit confirmation for execution.
- Always ask for explicit confirmation before performing state-changing or destructive Git operations (e.g., commit, push, reset, checkout that overwrites, etc.). Non-destructive, read-only commands (e.g., status, diff, log, show) can be run without prompting.


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
