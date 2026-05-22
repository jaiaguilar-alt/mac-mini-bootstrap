# mac-mini-bootstrap

Bootstrap scripts to turn a fresh Mac Mini into the new local-node half of Jai's Pax stack. Designed to be run on **macOS** (Apple Silicon or Intel) once the device is unboxed and signed into iCloud + 1Password.

This replaces the Windows laptop's role per `pax-memory/projects/mac-mini-laptop-transition.md`. The droplet (the always-on cloud half) is unchanged.

## Pre-bootstrap (manual — needed once before running anything here)

1. Finish standard macOS setup (Apple ID, FileVault, name the machine `JaiMini` or similar).
2. Install **1Password desktop app** from the App Store, sign in with the master password, and enable the **CLI integration** (Settings → Developer → "Integrate with 1Password CLI"). This is the gate everything else depends on — the bootstrap scripts read secrets from 1P.
3. Install **Google Chrome**, sign in with `jai@flowautobody.com.au`. Chrome Sync brings bookmarks + extensions over automatically.
4. Install **Google Drive Desktop**, sign in. `~/Google Drive/My Drive/Claude-AI Projects/` will sync down from the cloud — including the Windows-laptop parachute snapshot.
5. Open a Terminal window and run:

   ```bash
   xcode-select --install        # accept the prompt; ~10 minutes
   ```

6. Once Command Line Tools are installed, clone this repo and run the bootstrap:

   ```bash
   git clone https://github.com/jaiaguilar-alt/mac-mini-bootstrap.git
   cd mac-mini-bootstrap
   ./scripts/bootstrap.sh
   ```

## What `bootstrap.sh` does

The script is idempotent — safe to re-run. It runs in clearly labeled phases.

| Phase | What |
|---|---|
| 0 | Verify 1Password CLI signed in (`op vault list` works) |
| 1 | Install Homebrew + base tools (`node`, `gh`, `git`, `op`, `cloudflared`, `jq`, `ripgrep`) |
| 2 | Install Claude Code CLI globally (`npm install -g @anthropic-ai/claude-code`) |
| 3 | Generate fresh SSH keys (`mac_mini_github`, `mac_mini_droplet`); add SSH config alias for droplet |
| 4 | `gh auth login` using GitHub PAT from 1P; optionally register the SSH key with GitHub |
| 5 | Clone every `jaiaguilar-alt/*` repo into `~/projects/` (skips pax-memory + deprecated) + clone Flow-Media-Digital workflow-prototype + workflow-widget |
| 5b | Clone `pax-memory` to `~/.openclaw/pax-memory/` (separate from working repos; required for hooks + memory continuity) |
| 6 | Load Claude Code subscription OAuth token from 1P into `CLAUDE_CODE_OAUTH_TOKEN` env (appended to `~/.zshenv` so non-interactive subshells — e.g. Claude Code Desktop's Bash tool — inherit it too). Migrates any prior `~/.zshrc` install. |
| 7 | Install MCP server packages + write Mac-flavoured launchers in `~/.pax-mcp-launchers/` + `claude mcp add` for Notion, Xero, Slack, Drive |
| 8 | Restore Drive OAuth keys from 1P (refresh tokens regen fresh via `mcp-server-gdrive auth`) |
| 9 | Verify droplet reachable via SSH (`ssh pax-cloud-droplet echo ok`) |
| 10 | Configure `~/.claude/settings.json` with SessionStart/Stop hooks pointing at `~/.openclaw/pax-memory/scripts/mac-mini-*.sh` |

## What's NOT in `bootstrap.sh`

These need manual decisions or external action:

- **Add Mac Mini SSH key to droplet** — Phase 9 detects + reminds. Run once from a machine that already has droplet access.
- **Tahir's Bitbucket repos** (`workflow-autobody/flow`, `workflow-autobody/workflowmvp-admin`, etc.) — not in `jaiaguilar-alt/`; Tahir owns those. Clone manually only if a working copy is wanted.
- **Reformatting the Windows laptop** — happens AFTER this bootstrap proves the Mac Mini is fully operational for ≥48h.

## What's no longer in scope (RETIRED 2026-05-22)

- **Telegram dispatch listener (`@ClaudeJaiLocal_bot`)** and **Discord dispatch listener (`ClaudeCode (Dispatch)`)** were retired. Droplet's `/ask` covers phone-driven dispatch. No launchd plist port.

## Things that come from 1P

All read from vault `pax-cloud-secrets` via `op://` references:

| Item | Used for |
|---|---|
| `GitHub PAT - pax-cloud` | `gh auth login`, git HTTPS auth |
| `Claude Code OAuth Token` | `CLAUDE_CODE_OAUTH_TOKEN` env for `claude -p` under subscription |
| `Notion PAT - pax-cloud` | Notion MCP launcher |
| `Xero Custom Connection - pax-cloud` | Xero MCP launcher (client_id + secret) |
| `Slack Bot Token - pax-cloud` | Slack MCP launcher |
| `Google Drive OAuth Keys - pax-cloud` (document) | Drive MCP — `gcp-oauth.keys.json` |
| `SSH private key - pax_cloud_deploy` (document) | Restore droplet SSH key (optional — script generates fresh by default) |
| `DigitalOcean - pax-cloud droplet` (document) | DO token + droplet metadata (added 2026-05-22) |
| `SSH private/public key - id_ed25519 (laptop default)` | Laptop backup; Mac generates fresh |

## Related repos

- `jaiaguilar-alt/pax-memory` — canonical memory. Cloned to `~/.openclaw/pax-memory/` in Phase 5b.
- `jaiaguilar-alt/pax-cloud` — the droplet bot. Mac Mini SSHs into it for ops.
- `jaiaguilar-alt/pax-relay` — the local HTTP bridge to Mission Control. Optional launchd port if Mac Mini is to expose pax-relay (separate task; not in this bootstrap).
- `jaiaguilar-alt/pax-workspace` — home dir state (migrated from Bitbucket 2026-05-22). Cloned to `~/projects/pax-workspace/`.

## Order of the day Mac Mini lands

1. Unbox, macOS setup, sign into iCloud + 1P + Drive + Chrome
2. Run pre-bootstrap manual steps above
3. `git clone` this repo and run `bootstrap.sh`
4. Verify smoke tests:
   - `claude -p "hello"` works under subscription
   - `gh repo list jaiaguilar-alt | head` works
   - `ssh pax-cloud-droplet hostname` works (after dropping public key on droplet)
   - Open Claude Code app, start session, check `~/.openclaw/pax-memory/agents/claudecode-macmini/sync.log` for session-start entry
5. Run ≥48h on Mac Mini alongside the Windows laptop; verify day-to-day workflow is happy
6. Then plan the Windows laptop reformat for Camina handover
