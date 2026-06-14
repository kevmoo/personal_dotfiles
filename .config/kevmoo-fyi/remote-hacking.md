# The plan — in-browser desktop from a locked-down corp machine

> Status: **final design, nothing run yet.** The public step (Funnel) needs explicit go.

## Decisions (locked)
- **Client:** locked-down corp machine, **browser only**, can't join tailnet → reach via **public URL** (Tailscale **Funnel**). Gmail confirmed reachable on the corp box.
- **Stack:** clientless **Guacamole** desktop over **RDP** (Sunshine ruled out — Appendix B).
- **Auth:** **`oauth2-proxy` + Google** in front of Guacamole. No Postgres. Ride your Google account's 2FA. Allowlist = your email only.
- **Display:** monitor attached → share the live GNOME session.

## Phase 1 — DONE (RDP backend verified)
- `gnome-remote-desktop 50.1`: RDP **enabled, active, View-only off**. Cert+creds pre-provisioned (user `kevmoo`).
- Loopback RDP verified **end-to-end**: negotiation + full **TLSv1.3 handshake** succeed; server requires **CredSSP/NLA**, self-signed cert delivered. *(Phase 2: guacd needs `security=nla`, credentials, ignore self-signed cert; fingerprint `f6:d9:e2:db:e0:af:…`.)*
- Note: native-RDP TLS failures seen from an external client (`17:19`/`17:33`) were **client-side** (cert rejection) — server TLS is fine. **Native RDP is N/A for browser-only devices** (no Tailscale client, no LAN when traveling); they must use the Guacamole+Funnel URL.
- **3389 reachable over the tailnet only.** Firewall locked down: `tailscale0` moved to firewalld `trusted` zone (keeps tailnet RDP); LAN zone (`wlp4s0`) gets a `priority="-100"` drop on 3389 (beats the blanket 1025-65535 allow). Loopback stays open for guacd. Net: LAN=blocked, tailnet=open, loopback=open. Not internet-exposed.
- TODO: rotate the RDP password (auto-gen one was printed to the session transcript).
- Reversible: `grdctl rdp disable`.

## Phase 2 — DONE (Guacamole desktop in browser, verified)
- Podman pod `guac` (loopback only): `guacd` + `guacamole`, published `127.0.0.1:8090` (8080 was taken by a local `dart:server`).
- Config at `~/.config/guacamole/guac-home/` (`user-mapping.xml` + `guacamole.properties`), mounted `:Z` for SELinux.
- guacd reaches the host RDP backend via **`host.containers.internal:3389`** (resolves `169.254.1.2`, not firewall-blocked).
- Gotcha fixed: mapped container uid (1001) couldn't read `600` config → set `644`.
- **Verified end-to-end**: browser → Guacamole (`admin`/`guac-admin-phase2`) → guacd → RDP → live desktop renders + input works.
- TODO before going public: pod is **ephemeral** (no reboot persistence yet — quadlet/systemd in Phase 3/4); `user-mapping.xml` holds RDP password in plaintext `644` (acceptable local; oauth2-proxy fronts it next).

## Phase 3 — DONE (Google auth in front, verified)
- `oauth2-proxy` added to the pod as the **front door** on `127.0.0.1:8091`; Guacamole no longer published directly (only reachable through the proxy — verified unauth `/guacamole/` → 403).
- Google OAuth client (Testing mode, self as user). Config in `~/.config/oauth2-proxy/` (`oauth2-proxy.env` 600 holds client id/secret/cookie secret; `authenticated-emails.txt` = `kevmoo16@gmail.com`).
- **Verified**: full double-login flow (Google → Guacamole `admin`) → desktop; every request stamped `kevmoo16@gmail.com`; non-allowlisted Google accounts can't pass oauth2-proxy.
- TODO for Phase 4 (going public): change `OAUTH2_PROXY_REDIRECT_URL` → `https://bluefin.tailba5047.ts.net/oauth2/callback`, set `COOKIE_SECURE=true`, set `--trusted-proxy-ip` to the Funnel/loopback source, then enable Funnel.

## 🏁 GOAL ACHIEVED — verified from an external Mac browser (no Tailscale client): Google login → Guacamole → live Bluefin desktop over the internet.
Notes: use the full path `https://bluefin.tailba5047.ts.net/guacamole/` (bare root 404s — declined a redirect). Keyboard: Guacamole forwards physical scancodes, so Dvorak-on-Mac garbled because the host session was QWERTY-primary; set GNOME input source order to Dvorak-first (`us+dvorak`,`us`) — testing whether gnome-remote-desktop honors it vs overriding from the RDP-announced layout.

## Phase 4 — Funnel LIVE (public, pending external browser confirmation)
- **Public URL: `https://bluefin.tailba5047.ts.net/`** → Funnel → `127.0.0.1:8091` (oauth2-proxy).
- Required: Funnel enabled in admin console (tailnet capability) + `tailscale set --operator=kevmoo` (so funnel on/off needs no sudo).
- oauth2-proxy in HTTPS mode (`COOKIE_SECURE=true`, redirect → funnel hostname). Guacamole admin password set to a user-chosen value.
- Smoke test over HTTPS: valid cert, sign-in 200, unauth `/guacamole/` → 403, oauth2-proxy stays loopback-only. ✅
- **Kill switches:** local `tailscale funnel reset` (instant) or `podman pod stop guac`; site: revoke Funnel attr in admin console (tailnet-wide).
- Remaining hardening: (a) optional `--trusted-proxy-ip`; (b) decide Funnel always-on vs on-demand; (c) rotate transcript-leaked RDP password.

## Phase 5 — Persistence (DONE)
- Converted to **Podman Quadlet** units in `~/.config/containers/systemd/` (`guac.pod`, `guac-guacd.container`, `guac-guacamole.container`, `guac-oauth2-proxy.container`); `Restart=always`. `loginctl enable-linger kevmoo` (Linger=yes) so containers start at boot. Verified stack restarts under systemd + public URL still works.
- **Reboot caveat (IMPORTANT):** `gnome-remote-desktop` shares the *active GNOME login session*. Autologin is **NOT** enabled → after a reboot the box sits at GDM and there's **no session to share** until someone logs in. Funnel + containers come back, but RDP has no desktop until login.
- **Decision: leave autologin OFF.** Root is **passphrase-only LUKS** (`nvme0n1p3`; clevis installed but **not** bound — verified `clevis luks list` empty). So a reboot-while-away already halts at the pre-boot disk passphrase prompt (no network/Tailscale/containers yet) → unreachable until physically present regardless of autologin. Autologin would only save the 2nd (GNOME) login when you're already there to type the disk passphrase = near-zero benefit, small physical-access cost. After any reboot: disk passphrase + GNOME login in person, then remote works.
- **If unattended reboot-recovery is ever wanted:** TPM auto-unlock (`clevis…tpm2`)+autologin, or dropbear-initramfs SSH unlock, or Clevis+Tang on the tailnet — each a separate project with real at-rest-security tradeoffs.

## Phase 6 — Capture watchdog (auto-lock kept)
- Problem: screen auto-blanks at 5-min idle (`idle-delay=300`); when blanked, `gnome-remote-desktop` gets stuck "Failed to record monitor: Unknown monitor" → next remote connect fails. Auto-lock is **required** (13yo in the house), and GNOME couples blank→lock, so can't keep lock without blank.
- Fix: **`grd-watchdog`** user service (`~/.config/grd-watchdog.sh` + `~/.config/systemd/user/grd-watchdog.service`, enabled, linger-persistent). Event-driven `journalctl --follow` on gnome-remote-desktop; on "Failed to record monitor" it calls `org.gnome.ScreenSaver.SimulateUserActivity` (wakes display to the LOCK screen, does NOT unlock) + restarts gnome-remote-desktop. 15s debounce. ~20MB RSS, 0% CPU idle.
- Behavior: reactive → after a blank, the **first** connect may fail, watchdog heals (~few s), **retry works** (shows lock screen → unlock remotely). Could be made proactive (restart on screensaver-active) if the one-retry annoys. Manual recovery fallback: Tailscale SSH + `systemctl --user restart gnome-remote-desktop` (SSH-on-SELinux unverified).
- TODO: user to verify by locking screen / waiting for blank, then reconnecting from Mac.

## Phase 7 — REGRESSION + rollback (session crash on resolution change)
- **What happened:** GNOME Shell **SIGSEGV** (coredump, 11:32:45) on an RDP-driven resolution/monitor change → full session logout, apps closed, "session forcibly closed". `dash-to-dock` "needs an allocation" storm = extension choking on the monitor geometry change (likely contributor; extensions run in-process in gnome-shell).
- **Cause (mine):** `resize-method=display-update` in the RDP connection forced **physical** monitor mode-changes on the active session every browser resize; the `grd-watchdog` restarting capture mid-resize likely compounded it (screencast teardown).
- **Rollback:** removed `resize-method` from user-mapping.xml (backup `.bak`) → browser can no longer trigger host mode-changes; it shares the current screen (4K) and **scales in the browser**. **Disabled** `grd-watchdog` (removed that variable). Stack verified healthy after.
- **Now un-mitigated again:** the 5-min blank→capture-stuck issue (Phase 6) returns with the watchdog off. Needs a *gentler* fix (NOT restarting grd mid-screencast). Open.
- **Tradeoff accepted:** remote view = host native res scaled in browser (stable) vs. client-matched res (crashed). Physical monitor *switching* is a separate geometry-change risk, not covered by this fix.

## Phase 8 — DONE (dummy plug + Dvorak keyboard, verified 2026-06-07)
- **Headless display via dummy plug — SOLVED.** UGREEN HDMI dummy in use. **Mirror** the real monitor + dummy (GNOME Settings → Displays → *Mirror*) so they're **one logical monitor** — then unplugging the real monitor collapses to the dummy with **zero layout change** (no primary shuffle, no dash-to-dock crash). **Verified:** pulled the Samsung → session stayed alive on the dummy, gnome-shell PID unchanged, no coredump. Dummy currently on **card0-HDMI-A-2 (the Radeon dGPU's HDMI)** = single-GPU, cleaner than the motherboard/iGPU port. *Caveat:* dGPU has only one HDMI (shared with the Samsung) → swap plugs when going local↔remote. To avoid swapping: a **DisplayPort dummy** on a free dGPU DP port lets both coexist permanently.
- **Dvorak keyboard — SOLVED.** Root cause: **guacd always sends QWERTY scancodes** (`en-us-qwerty`), so the **host's active layout must be plain `us` (QWERTY)** or it double-translates → garbage. Fix: **keep the Mac on Dvorak**, flip the **host** to QWERTY for the remote session (one click on the lock-screen layout chooser, or **Super+Space** once in; flip back to Dvorak for local use). This corrects the earlier WRONG attempt (setting the host to `us+dvorak` primary — that *caused* the double-map). `server-layout=failsafe` (Unicode injection) was tried and **does NOT work** with gnome-remote-desktop 50.1 (it loaded but typing stayed garbled) — reverted. Boot chain is all Dvorak by default (LUKS `us-dvorak`, GDM `us/dvorak`), which suits local use; GDM shows a layout switcher only if 2+ system layouts are configured (currently 1).

## OPEN FOLLOW-UPS (resume here)
1. **Idle-blank capture recovery (gentle) — RESOLVED.** Installed the GNOME Shell extension `Unblank lock screen` (`unblank@sun.wxg@gmail.com`). This extension prevents the display output from entering DPMS sleep when the screen locks, meaning the display remains active and `gnome-remote-desktop` always succeeds on connect. *Note:* Requires a logout/login (or reboot) for GNOME Shell to discover the extension, after which it can be enabled via `gnome-extensions enable unblank@sun.wxg@gmail.com`.
2. **Optional: auto-switch keyboard layout — DECLINED (Simplicity First).** Decided to keep layout switching manual (pressing `Super+Space` or using the lock screen selector) to avoid adding fragile GSettings workarounds or background watchers under GNOME Shell Wayland.
3. **Optional: DisplayPort dummy** — to avoid swapping the HDMI dummy with the Samsung each local↔remote transition.

## This machine (verified)
Bluefin-DX 44, GNOME **Wayland**. Tailscale up, tailnet IP **`100.70.234.26`** (`bluefin`). Podman 5.8.2. `/dev/uinput` present. Path layers **nothing** via rpm-ostree — all containers + built-in `gnome-remote-desktop`. Clean for an atomic OS.

## Architecture
```
Corp browser
  │ HTTPS (public 443, real Let's Encrypt cert, home IP hidden)
  ▼
Tailscale Funnel  ── double opt-in, instant `funnel off` kill switch
  │
  ▼
oauth2-proxy (127.0.0.1)  ── Google login here. Allowlist = your email. --trusted-proxy-ip locks header trust.
  │  forwards X-Auth-Request-User on success
  ▼
Guacamole (127.0.0.1, header-auth extension)  ── trusts the header → SSO, no second login
  │
  ▼
guacd (127.0.0.1)
  │ RDP
  ▼
gnome-remote-desktop (127.0.0.1)  ── shares your live GNOME Wayland session
  │
  ▼
Your desktop
```
Only the Funnel ingress is public; everything else is loopback (also off the LAN). The internet **never reaches Guacamole** until Google vouches for you — that's the main reason for the proxy.

---

## Build phases (proposed)

**Phase 1 — RDP backend (host, fully local & reversible).**
- Generate a self-signed TLS key/cert (loopback-only → self-signed is fine).
- `grdctl rdp set-tls-key/cert`, `grdctl rdp set-credentials <user> <pass>`, `grdctl rdp enable`.
- Verify: an RDP client on the host (loopback) connects and shows the desktop.
- *Reversible:* `grdctl rdp disable`. Touches nothing public.

**Phase 2 — Guacamole + guacd (podman pod, bound to 127.0.0.1).**
- `guacd` + `guacamole`, one RDP connection → `127.0.0.1` (gnome-remote-desktop).
- Start with `user-mapping.xml` (single account) to prove the chain locally at `localhost`.
- Verify: browser on host → Guacamole → your desktop renders + input works.

**Phase 3 — oauth2-proxy + Google (still local).**
- One-time: register a Google OAuth client (Cloud Console), redirect URI = the Funnel hostname `https://bluefin.<tailnet>.ts.net/oauth2/callback`.
- Run `oauth2-proxy` (loopback) → upstream Guacamole; cookie secret; **email allowlist = your address**; `--trusted-proxy-ip` for the Funnel relay.
- Switch Guacamole to the **header-auth** extension so the proxy's `X-Auth-Request-User` = single sign-on.
- Verify locally: hitting the proxy port forces Google login, then lands in the desktop.

**Phase 4 — expose via Funnel (THE public step — explicit go required).**
- Enable Funnel in Tailscale admin console (double opt-in) + on this device.
- `tailscale funnel` → public 443 reverse-proxies to the oauth2-proxy loopback port.
- Public URL: `https://bluefin.<your-tailnet>.ts.net/`.

**Phase 5 — verify & lock down.**
- From an **off-tailnet** browser: confirm Google login is forced, non-allowlisted accounts are rejected, desktop works.
- Confirm Guacamole is unreachable without the proxy (try the guac port directly — should be loopback-only).

---

## Hardening checklist (it's public)
- [ ] oauth2-proxy email allowlist = exactly your address; `--trusted-proxy-ip` set.
- [ ] Everything but Funnel bound to `127.0.0.1` (off the LAN too).
- [ ] Separate creds: gnome-remote-desktop (RDP) ≠ anything else.
- [ ] **Funnel as on-demand kill switch:** consider `tailscale funnel off` when not traveling, toggled from a phone on the tailnet. Smaller exposure window.
- [ ] Containers in a **pod + quadlet/systemd** so they survive reboot; pin digests / `podman auto-update`.
- [ ] **Corp-side reality:** the corp browser may be screenshot/keylogged by MDM/DLP — don't show home secrets through it; check corp acceptable-use policy re: tunneling to personal remote-desktop. Your call, flagging neutrally.

## Open knobs (defaults I'll assume unless you say otherwise)
1. Pod + quadlet for reboot-persistence — **yes** unless you object.
2. Funnel on-demand vs always-on — **on-demand** (smaller window) unless you want always-on convenience.
3. Validate each phase locally before the next — **yes**.

---

## Appendix A — corrected facts from the Gemini doc
- `ghcr.io/moonlight-stream/moonlight-web-stream` **doesn't exist**; real one is unofficial `docker.io/mrcreativ3001/moonlight-web-stream`.
- Sunshine `origin` / `ip_whitelist` keys **aren't real**; real ones: `origin_web_ui_allowed`, `address_family`, `bind_address`. Real access control = Tailscale ACLs.
- `rpm-ostree reload` **doesn't apply** a layered package — reboot.
- Tailscale was **already set up** here; Step 1 was moot.

## Appendix B — why not Sunshine
- Sunshine shines for **gaming + native clients**; our client is a **browser on a locked-down corp box** and the use is desktop access.
- Its only browser path is an **unofficial single-maintainer WebRTC proxy** that also injects input — heavy trust cost in a *public* path.
- It wants **WebRTC/UDP**, but **Funnel is TCP/HTTPS-only** → forces the proxy's WebSocket fallback, at which point Guacamole (purpose-built clientless HTTPS, audited) is the better tool.
- Sunshine on **GNOME Wayland** is the fiddly capture case; Guacamole+RDP via `gnome-remote-desktop` is the supported Wayland path.
- Still a fun **separate** gaming experiment later if you want.

## Appendix C — why no Postgres / why oauth2-proxy
- Postgres was only ever for **Guacamole's TOTP storage**. Using Google via oauth2-proxy removes that need entirely.
- **Funnel publishes to the anonymous public internet** (unlike `tailscale serve`, which keeps Tailscale device-identity as auth). So Tailscale gives transport encryption + IP hiding + kill switch, but **not** visitor auth — the app front door is the only gate, which is why a strong, isolating auth proxy matters.

### Sources
- gnome-remote-desktop / grdctl: https://github.com/GNOME/gnome-remote-desktop , https://jamesnorth.net/post/grd-46-setup
- Guacamole reverse-proxy + header auth: https://guacamole.apache.org/doc/gug/reverse-proxy.html
- oauth2-proxy: https://github.com/oauth2-proxy/oauth2-proxy
- Guacamole OIDC (auth layered on connection source): https://guacamole.apache.org/doc/gug/openid-auth.html
- Tailscale Funnel (TCP/HTTPS only, double opt-in, hides IP): https://tailscale.com/docs/features/tailscale-funnel
