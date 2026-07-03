---
name: upkeep
description: Check the status of system tools (mise, brew, dotfiles, skills, scripts.dart, ujust) and apply updates across Mac and Linux.
---

# System Upkeep Skill

Use the `upkeep` CLI executable to audit system status, list available adapters, and update machine components.

## Subcommands Overview

| Subcommand | Description | Example |
| :--- | :--- | :--- |
| `upkeep check` | Non-destructive status audit across upkeepers | `upkeep check --json` |
| `upkeep update` | Apply updates for target or outdated upkeepers | `upkeep update --yes` |
| `upkeep list` | List registered upkeepers and host support status | `upkeep list` |

## 1. Non-Destructive Status Audit (`upkeep check`)
To inspect status across all upkeepers as machine-readable JSON:
```bash
upkeep check --json
```
To check specific upkeepers:
```bash
upkeep check brew mise
# or
upkeep check -k brew,mise
```

## 2. Applying Updates (`upkeep update`)
To apply updates across all outdated subsystems non-interactively:
```bash
upkeep update --yes
```
To update specific upkeepers directly:
```bash
upkeep update brew
```

## 3. Adapter Registry (`upkeep list`)
To list registered upkeepers and check support status on the current host:
```bash
upkeep list
```
