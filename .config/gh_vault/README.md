# `gh_vault` — Agent-Safe GitHub CLI Elevation Vault

A zero-daemon, cross-platform security boundary for the GitHub CLI (`gh`) across macOS (Intel & Apple Silicon), corp gLinux, and personal Linux workstations.

It enforces the principle of least privilege for daily AI agent and interactive workflows while supporting explicit, password-gated privilege elevation via `sudo`.

---

## 1. How It Works

```
┌─────────────────────────────────────────────────────────────┐
│ 95% Daily Operations (Default Restricted Baseline)          │
│ • Runs under Fine-Grained Personal Access Token (PAT)       │
│ • Full access: PRs, Issues, Commit pushes, CI checks        │
│ • Hard Blocked: Repo deletion, settings, rulesets, secrets   │
└─────────────────────────────────────────────────────────────┘
                               ▲
           sudo gh-unlock [min]│  │ 5-min passive expiry (or gh-lock)
                               ▼
┌─────────────────────────────────────────────────────────────┐
│ 5% Administrative Operations (Elevated Window)              │
│ • Injects full Admin PAT from /etc/github/admin.token       │
│ • Stored in RAM tmpfs (/run/user/$UID or /private/tmp)       │
│ • Full access: Branch protection, repo settings, deletion    │
└─────────────────────────────────────────────────────────────┘
```

1. **Baseline Mode**: Your daily `gh` session uses a restricted **Fine-Grained PAT** in `~/.config/gh/hosts.yml` or the system keyring. The GitHub REST API physically rejects destructive repo modifications with `HTTP 403 Forbidden`.
2. **Elevation Mode**: Running `sudo gh-unlock 5` reads your high-privilege Admin PAT from `/etc/github/admin.token` and atomically writes a 5-minute lease JSON to volatile RAM tmpfs (`0600` user permissions).
3. **Transparent Dispatcher**: The `~/.local/bin/gh` binary checks for an active lease on every call. If valid, it transparently passes `GH_TOKEN="<admin_token>"` to upstream `gh`.
4. **Passive Auto-Expiry**: When the timestamp expires (or when running `gh-lock`), the dispatcher unlinks the lease file and reverts immediately to restricted baseline privileges.

---

## 2. CLI Commands

* **`sudo gh-unlock [minutes]`**: Elevates `gh` privileges for the specified duration (default: `5` minutes).
* **`gh-lock`**: Revokes the active elevation lease immediately, dropping back to restricted mode.
* **`sudo gh-unlock --init`**: Interactively creates or updates the root vault at `/etc/github/admin.token` with masked input.
* **`gh <command>`**: Regular GitHub CLI commands. Transparently elevated if a lease is active.

---

## 3. System File Inventory

<!-- mdformat off(prevent table wrapping) -->
| Path | Ownership | Permissions | Purpose |
| :--- | :--- | :--- | :--- |
| **`/etc/github/admin.token`** | `root:root` | `0600` (`rw-------`) | Contains your high-privilege GitHub Admin PAT. |
| **`/usr/local/bin/gh-unlock`** | `root:root` | `0755` (`rwxr-xr-x`) | Standalone AOT binary for `sudo gh-unlock [minutes]`. |
| **`~/.local/bin/gh`** | User | `0755` (`rwxr-xr-x`) | Dispatcher shadowing system `gh` on user PATH. |
| **`~/.local/bin/gh-lock`** | User | `0755` (`rwxr-xr-x`) | Revocation tool unlinking the active lease. |
| **`/run/user/$UID/gh_vault/lease.json`** | User | `0600` (`rw-------`) | Volatile RAM lease (Linux `tmpfs`). Auto-unlinked on expiry. |
| **`/private/tmp/.gh_vault_$UID/lease.json`** | User | `0600` (`rw-------`) | Volatile lease (macOS `0700` dir). Auto-unlinked on expiry. |
<!-- mdformat on -->

---

## 4. Setup on a New Machine (macOS or Linux)

### Step 1: Generate Tokens on GitHub

1. **Baseline Token (Fine-Grained PAT)**:
   * Go to **GitHub Settings > Developer settings > Personal access tokens > Fine-grained tokens**.
   * Permissions:
     * *Pull requests*: Read and write
     * *Issues*: Read and write
     * *Contents*: Read and write
     * *Actions*: Read-only
     * *Commit statuses*: Read-only
     * *Metadata*: Read-only
     * *Administration / Secrets / Rules*: **No access**
   * Log in to `gh` using this token:
     ```bash
     echo "<BASELINE_FINE_GRAINED_PAT>" | gh auth login --with-token
     ```

2. **Admin Vault Token (Fine-Grained or Classic PAT)**:
   * Permissions: `Administration` (Read & write), `Secrets` (Read & write), `Contents` (Read & write), `Pull requests` (Read & write).

### Step 2: Compile & Install Binaries

```bash
# 1. Compile standalone AOT binaries
dart compile exe ~/.config/gh_vault/bin/gh_dispatch.dart -o ~/.local/bin/gh
dart compile exe ~/.config/gh_vault/bin/gh_lock.dart     -o ~/.local/bin/gh-lock
dart compile exe ~/.config/gh_vault/bin/gh_unlock.dart   -o /tmp/gh-unlock

# 2. Install gh-unlock to system path
sudo install -m 0755 /tmp/gh-unlock /usr/local/bin/gh-unlock
rm -f /tmp/gh-unlock

# 3. Initialize the root vault
sudo gh-unlock --init
```

---

## 5. Complete Teardown & Uninstall

To remove `gh_vault` and restore default `gh` behavior:

```bash
# 1. Remove root vault and unlock tool
sudo rm -rf /etc/github /usr/local/bin/gh-unlock

# 2. Remove user dispatchers
rm -f ~/.local/bin/gh ~/.local/bin/gh-lock

# 3. Log in standard gh
gh auth login
```
