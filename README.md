# mac-mini-bootstrap

Bootstrap scripts and launchd plists to turn a fresh Mac Mini into the new local-node half of Jai's Pax stack. Designed to be run on **macOS** (Apple Silicon or Intel) once the device is unboxed and signed into iCloud + 1Password.

This replaces the Windows laptop's role per `pax-memory/projects/mac-mini-laptop-transition.md`. The droplet (the always-on cloud half) is unchanged.

## Pre-bootstrap (manual — needed once before running anything here)

1. Finish standard macOS setup (Apple ID, FileVault, name the machine `JaiMini` or similar).
2. Install **1Password desktop app** from the App Store, sign in with the master password, and enable the **CLI integration** (Settings → Developer → "Integrate with 1Password CLI"). This is the gate everything else depends on — the bootstrap scripts read secrets from 1P.
3. Install **Google Chrome**, sign in with `jai@flowautobody.com.au`. Chrome Sync brings bookmarks + extensions over automatically.
4. Open a Terminal window and run:

   ```bash
   xcode-select --install        # accept the prompt; ~10 minutes
   ```

5. Once Command Line Tools are installed, clone this repo:

   ```bash
   git clone https://github.com/jaiaguilar-alt/mac-mini-bootstrap.git
   cd mac-mini-bootstrap
   ./scripts/bootstrap.sh
   ```

## What `bootstrap.sh` does

The script is idempotent — safe to re-run. It runs in clearly labeled phases and asks confirmation before any destructive or external-effect step.

| Phase | What |
|---|---|
| 0 | Confirm 1Password CLI is signed in (`op vault list` works) |
| 1 | Install Homebrew + base tools (`node`, `gh`, `git`, `op`, `cloudflared`, `jq`, `ripgrep`) |
| 2 | Install Claude Code CLI globally (`npm install -g @anthropic-ai/claude-code`) |
| 3 | Generate fresh SSH keys (`mac_mini_github`, `mac_mini_droplet`), register with GitHub via `gh`, prompt Jai to add droplet key to `pax@134.199.144.22:~/.ssh/authorized_keys` |
| 4 | `gh auth login --with-token` using the GitHub PAT from `op://pax-cloud-secrets/GitHub PAT - pax-cloud/credential` |
| 5 | Clone every `jaiaguilar-alt/*` repo into `~/projects/` (skips repos already cloned) |
| 6 | Load Claude Code subscription OAuth token from `op://pax-cloud-secrets/Claude Code OAuth Token/credential` into `CLAUDE_CODE_OAUTH_TOKEN` env (added to `~/.zshrc`) |
| 7 | Install MCP server packages and register the four launchers (Notion, Xero, Slack, Drive) — same wrappers used on the droplet, but reading 1P via the Mac's `op signin` device trust |
| 8 | Restore Google Drive OAuth keys + cached credentials to `~/.gdrive-auth/` from 1P backup |
| 9 | Verify droplet reachable via SSH (`ssh pax@134.199.144.22 echo ok`) |
| 10 | Optional: install launchd plists from `./launchd-plists/` to port the Telegram + Discord dispatch listeners. **Skipped by default** — Jai needs to decide whether to port or retire those listeners (the droplet's `/ask` covers the same use case) |

## What's NOT in `bootstrap.sh`

These need manual decisions, so they're out of the script:

- **OpenClaw node** — depends on whether Jai keeps the laptop's OpenClaw node-only architecture or simplifies. Run `~/.openclaw/node.cmd`-equivalent manually after deciding.
- **Reformatting the Windows laptop** — happens AFTER this bootstrap proves the Mac Mini is fully operational.
- **Tahir's Bitbucket repos** (`workflow-autobody/flow`, `workflow-autobody/workflowmvp-admin`) — clone manually if a working copy is wanted; they're not in `jaiaguilar-alt/` and Jai isn't the owner.

## launchd-plists/

Two plists template the Telegram + Discord dispatch listeners as launchd jobs (equivalent of the Windows `pax-stack-watchdog.ps1` scheduled task). Only used if Jai chooses to port the listeners; copy to `~/Library/LaunchAgents/` and `launchctl load <plist>`.

- `com.jai.pax.telegram-dispatch.plist`
- `com.jai.pax.discord-dispatch.plist`

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

## Related repos

- `jaiaguilar-alt/pax-cloud` — the droplet bot. Mac Mini SSHs into it for ops.
- `jaiaguilar-alt/pax-memory` — canonical memory. Mac Mini clones it to `~/.openclaw/pax-memory/`.
- `jaiaguilar-alt/pax-relay` — the local HTTP bridge to Mission Control. Runs on Mac Mini once a launchd port is written.
- `jaiaguilar-alt/pax-dispatch-listeners` — Telegram + Discord listeners; ported via plists if kept.

## Order of the day Mac Mini lands

1. Unbox, macOS setup, sign into iCloud + 1P
2. Install Chrome + sign in (bookmark sync runs in background)
3. Run pre-bootstrap manual steps above
4. `git clone` this repo and run `bootstrap.sh`
5. Verify: `claude -p "hello"` works, `gh repo list jaiaguilar-alt | head` works, `ssh pax@134.199.144.22 hostname` works
6. Decide on dispatch listener fate; load plists if porting
7. Once green, plan the Windows laptop reformat for handover to Camina
