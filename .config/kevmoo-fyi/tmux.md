# Tmux Cheat Sheet

[View `.tmux.conf`](../../.tmux.conf)

In `tmux`, everything starts with the **Prefix**: `Ctrl` + `b`. Press it, release, then hit the command key.

## Windows (Tabs)
| Action | Command |
| :--- | :--- |
| **New Window** | `Prefix` + `c` |
| **Next Window** | `Prefix` + `n` |
| **Previous Window** | `Prefix` + `p` |
| **Last Active Window** | `Prefix` + `Tab` |
| **Switch by Number** | `Prefix` + `0-9` |
| **Rename Window** | `Prefix` + `,` |
| **List Windows** | `Prefix` + `w` |

## Panes (Splits)
| Action | Command |
| :--- | :--- |
| **Split Vertically** | `Prefix` + `|` |
| **Split Horizontally** | `Prefix` + `-` |
| **Switch Panes** | `Prefix` + `h/j/k/l` (or Arrows) |
| **Resize Panes** | `Prefix` + `H/J/K/L` |
| **Swap Pane Forward** | `Prefix` + `>` |
| **Swap Pane Backward** | `Prefix` + `<` |
| **Close Pane** | `Ctrl` + `d` (or type `exit`) |

> **Note:** Mouse support is **off**. Use keyboard shortcuts for navigation and copying.

## Copy Mode & History
| Action | Command |
| :--- | :--- |
| **Enter Copy Mode** | `Prefix` + `[` (or scroll up) |
| **Exit Copy Mode** | `q` or `Enter` |
| **Scroll** | `Arrow Keys` or `Page Up/Down` |
| **Search (Up/Down)** | `/` or `?` |

## Sessions & Meta
| Action | Command |
| :--- | :--- |
| **Detach** | `Prefix` + `d` |
| **Reattach** | `tmux attach` |
| **Reload Config** | `Prefix` + `r` |
| **Edit Config** | `Prefix` + `e` |
| **Clear Screen/History** | `Ctrl` + `l` (no prefix) |
