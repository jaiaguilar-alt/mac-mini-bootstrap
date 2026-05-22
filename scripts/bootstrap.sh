#!/usr/bin/env bash
# Mac Mini bootstrap for Jai's Pax stack.
# Run AFTER signing into 1Password desktop app + enabling CLI integration.
# Idempotent — safe to re-run.
#
# Targets: macOS 14+ (Apple Silicon or Intel), zsh as login shell.
# Uses bash 3.2 compat (default macOS bash) — no associative arrays.

set -euo pipefail
trap 'echo "[FAIL] line $LINENO" >&2' ERR

# ────────────────────────────────────────────────────────────────────
# Config — edit if any of these change
# ────────────────────────────────────────────────────────────────────
GH_OWNER="jaiaguilar-alt"
DROPLET_HOST="134.199.144.22"
DROPLET_USER="pax"
PROJECTS_DIR="$HOME/projects"
PAX_MEMORY_DIR="$HOME/.openclaw/pax-memory"
OP_VAULT="pax-cloud-secrets"
SECRETS_REF_GITHUB_PAT="op://${OP_VAULT}/GitHub PAT - pax-cloud/credential"
SECRETS_REF_CLAUDE_OAUTH="op://${OP_VAULT}/Claude Code OAuth Token/credential"
SECRETS_REF_NOTION_PAT="op://${OP_VAULT}/Notion PAT - pax-cloud/credential"
SECRETS_REF_XERO_CLIENT_ID="op://${OP_VAULT}/Xero Custom Connection - pax-cloud/client_id"
SECRETS_REF_XERO_CLIENT_SECRET="op://${OP_VAULT}/Xero Custom Connection - pax-cloud/client_secret"
SECRETS_REF_SLACK_TOKEN="op://${OP_VAULT}/Slack Bot Token - pax-cloud/credential"
SECRETS_REF_SLACK_TEAM_ID="op://${OP_VAULT}/Slack Bot Token - pax-cloud/team_id"

# Repos to skip in the bulk clone (handled separately or deprecated)
# pax-memory: cloned to ~/.openclaw/pax-memory in phase_5b instead of ~/projects/
REPOS_TO_SKIP="pax-windows-tools-archive pax-memory"

# Additional non-jaiaguilar-alt repos to clone
EXTRA_REPOS="Flow-Media-Digital/workflow-prototype Flow-Media-Digital/workflow-widget"

# ────────────────────────────────────────────────────────────────────
# Helpers
# ────────────────────────────────────────────────────────────────────
log() { printf "\n\033[1;36m[%s]\033[0m %s\n" "$(date +%H:%M:%S)" "$*"; }
warn() { printf "\033[1;33m[warn]\033[0m %s\n" "$*" >&2; }
fail() { printf "\033[1;31m[fail]\033[0m %s\n" "$*" >&2; exit 1; }
ok() { printf "  \033[1;32m✓\033[0m %s\n" "$*"; }
note() { printf "  • %s\n" "$*"; }
confirm() {
  local prompt="$1"; local ans
  printf "\n\033[1;35m[?]\033[0m %s (y/N) " "$prompt"
  read -r ans
  [ "$ans" = "y" ] || [ "$ans" = "Y" ]
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

is_apple_silicon() { [ "$(uname -m)" = "arm64" ]; }

# ────────────────────────────────────────────────────────────────────
# Phase 0: 1Password CLI signed in
# ────────────────────────────────────────────────────────────────────
phase_0_op_signin() {
  log "Phase 0 — verify 1Password CLI"
  if ! command -v op >/dev/null 2>&1; then
    warn "op CLI not yet installed; will install in Phase 1"
    return
  fi
  if ! op vault list >/dev/null 2>&1; then
    fail "1Password CLI not signed in. Open the 1Password app → Settings → Developer → enable 'Integrate with 1Password CLI' and approve the prompt. Then re-run."
  fi
  ok "1Password CLI signed in"
  ok "vault '${OP_VAULT}' accessible: $(op item list --vault="${OP_VAULT}" --format=json 2>/dev/null | python3 -c 'import sys,json; print(len(json.load(sys.stdin)), "items")')"
}

# ────────────────────────────────────────────────────────────────────
# Phase 1: Homebrew + base tools
# ────────────────────────────────────────────────────────────────────
phase_1_brew() {
  log "Phase 1 — Homebrew + tools"
  if ! command -v brew >/dev/null 2>&1; then
    note "Installing Homebrew (will prompt for sudo password)"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if is_apple_silicon; then
      echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$HOME/.zprofile"
      eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
  fi
  ok "brew at $(which brew)"

  local pkgs="node gh git 1password-cli cloudflared jq ripgrep coreutils"
  for pkg in $pkgs; do
    if brew list "$pkg" >/dev/null 2>&1; then
      ok "$pkg already installed"
    else
      note "installing $pkg"
      brew install "$pkg"
      ok "$pkg installed"
    fi
  done
}

# ────────────────────────────────────────────────────────────────────
# Phase 2: Claude Code CLI
# ────────────────────────────────────────────────────────────────────
phase_2_claude_code() {
  log "Phase 2 — Claude Code CLI"
  if command -v claude >/dev/null 2>&1; then
    ok "claude already installed: $(claude --version)"
  else
    npm install -g @anthropic-ai/claude-code
    ok "claude installed: $(claude --version)"
  fi
}

# ────────────────────────────────────────────────────────────────────
# Phase 3: SSH keys
# ────────────────────────────────────────────────────────────────────
phase_3_ssh_keys() {
  log "Phase 3 — SSH keys"
  mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"

  local github_key="$HOME/.ssh/mac_mini_github"
  if [ ! -f "$github_key" ]; then
    ssh-keygen -t ed25519 -f "$github_key" -N "" -C "jai@mac-mini github $(date +%Y-%m-%d)"
    ok "generated $github_key"
  else
    ok "$github_key already exists"
  fi

  local droplet_key="$HOME/.ssh/mac_mini_droplet"
  if [ ! -f "$droplet_key" ]; then
    ssh-keygen -t ed25519 -f "$droplet_key" -N "" -C "jai@mac-mini droplet $(date +%Y-%m-%d)"
    ok "generated $droplet_key"
  else
    ok "$droplet_key already exists"
  fi

  # Append host entries to ssh config (idempotent)
  local cfg="$HOME/.ssh/config"
  touch "$cfg"; chmod 600 "$cfg"
  if ! grep -q "^Host pax-cloud-droplet" "$cfg"; then
    cat >> "$cfg" <<EOF

Host pax-cloud-droplet
  HostName ${DROPLET_HOST}
  User ${DROPLET_USER}
  IdentityFile ~/.ssh/mac_mini_droplet
  IdentitiesOnly yes
EOF
    ok "added pax-cloud-droplet host alias"
  fi

  note "GitHub public key (registered with GitHub in Phase 4):"
  cat "$github_key.pub"
  note "Droplet public key — paste into pax@droplet's ~/.ssh/authorized_keys:"
  cat "$droplet_key.pub"
}

# ────────────────────────────────────────────────────────────────────
# Phase 4: gh CLI auth
# ────────────────────────────────────────────────────────────────────
phase_4_gh_auth() {
  log "Phase 4 — GitHub auth"
  if gh auth status >/dev/null 2>&1; then
    ok "gh already authenticated as $(gh api user --jq .login)"
  else
    op read "$SECRETS_REF_GITHUB_PAT" | gh auth login --with-token
    gh auth setup-git
    ok "gh authenticated as $(gh api user --jq .login)"
  fi

  # Optional: register the fresh mac_mini_github key with GitHub
  if confirm "Register fresh Mac Mini SSH key with GitHub via gh?"; then
    gh ssh-key add "$HOME/.ssh/mac_mini_github.pub" --title "mac-mini-$(hostname -s)"
    ok "SSH key registered with GitHub"
  fi
}

# ────────────────────────────────────────────────────────────────────
# Phase 5: Clone all jaiaguilar-alt working repos to ~/projects/
# ────────────────────────────────────────────────────────────────────
phase_5_clone_repos() {
  log "Phase 5 — clone all ${GH_OWNER}/* working repos to ${PROJECTS_DIR}"
  mkdir -p "$PROJECTS_DIR"
  gh repo list "$GH_OWNER" --limit 100 --json name -q '.[].name' | while read -r r; do
    skip=0
    for s in $REPOS_TO_SKIP; do
      [ "$r" = "$s" ] && skip=1
    done
    [ $skip -eq 1 ] && { note "skip $r (handled separately or deprecated)"; continue; }
    if [ -d "$PROJECTS_DIR/$r" ]; then
      ok "$r already cloned"
    else
      gh repo clone "$GH_OWNER/$r" "$PROJECTS_DIR/$r" >/dev/null 2>&1
      ok "cloned $r"
    fi
  done

  log "Phase 5 cont. — clone extra repos (other orgs)"
  for full_repo in $EXTRA_REPOS; do
    name=$(basename "$full_repo")
    if [ -d "$PROJECTS_DIR/$name" ]; then
      ok "$name already cloned"
    else
      gh repo clone "$full_repo" "$PROJECTS_DIR/$name" >/dev/null 2>&1
      ok "cloned $full_repo → $name"
    fi
  done
}

# ────────────────────────────────────────────────────────────────────
# Phase 5b: Clone pax-memory to ~/.openclaw/pax-memory (NOT ~/projects/)
# ────────────────────────────────────────────────────────────────────
phase_5b_pax_memory() {
  log "Phase 5b — clone pax-memory to ${PAX_MEMORY_DIR}"
  mkdir -p "$(dirname "$PAX_MEMORY_DIR")"
  if [ -d "$PAX_MEMORY_DIR/.git" ]; then
    ok "pax-memory already cloned at $PAX_MEMORY_DIR"
    git -C "$PAX_MEMORY_DIR" pull --ff-only 2>&1 | tail -1
  else
    gh repo clone "${GH_OWNER}/pax-memory" "$PAX_MEMORY_DIR" >/dev/null 2>&1
    ok "cloned pax-memory to $PAX_MEMORY_DIR"
  fi

  # Verify identity file exists
  if [ -f "$PAX_MEMORY_DIR/identities/claudecode-macmini.md" ]; then
    ok "claudecode-macmini identity present"
  else
    warn "identities/claudecode-macmini.md NOT in pax-memory yet — pull may be needed or file missing upstream"
  fi
}

# ────────────────────────────────────────────────────────────────────
# Phase 6: Claude Code OAuth token in ~/.zshenv
# (must be .zshenv, not .zshrc — Claude Code Desktop's Bash tool spawns
# non-interactive zsh subshells that source .zshenv only.)
# ────────────────────────────────────────────────────────────────────
phase_6_claude_oauth() {
  log "Phase 6 — Claude Code subscription OAuth token (in ~/.zshenv)"
  local zshenv="$HOME/.zshenv"
  local zshrc="$HOME/.zshrc"
  local sentinel_begin="# >>> pax-bootstrap CLAUDE_CODE_OAUTH_TOKEN >>>"
  local sentinel_end="# <<< pax-bootstrap CLAUDE_CODE_OAUTH_TOKEN <<<"

  # Migration: earlier versions of this script appended the loader to ~/.zshrc,
  # which is only sourced by interactive shells. Claude Code Desktop's Bash tool
  # spawns non-interactive zsh subshells that source ~/.zshenv instead, so they
  # missed the token and `claude -p` failed with "Not logged in". Strip the
  # stale block from ~/.zshrc if present so it can be re-added to ~/.zshenv.
  if [ -f "$zshrc" ] && grep -qE '^[[:space:]]*export CLAUDE_CODE_OAUTH_TOKEN=' "$zshrc"; then
    note "migrating stale CLAUDE_CODE_OAUTH_TOKEN loader out of ~/.zshrc"
    cp "$zshrc" "$zshrc.pre-zshenv-migration.bak"
    awk '
      /^# Claude Code — subscription OAuth token loaded from 1P at shell start\.$/ { skipping = 1; next }
      skipping && /^fi$/ { skipping = 0; next }
      skipping { next }
      { print }
    ' "$zshrc" > "$zshrc.tmp" && mv "$zshrc.tmp" "$zshrc"
    ok "stripped stale loader from ~/.zshrc (backup at $zshrc.pre-zshenv-migration.bak)"
  fi

  touch "$zshenv"
  if grep -qF "$sentinel_begin" "$zshenv" || grep -qE '^[[:space:]]*export CLAUDE_CODE_OAUTH_TOKEN=' "$zshenv"; then
    ok "CLAUDE_CODE_OAUTH_TOKEN loader already in ~/.zshenv"
  else
    cat >> "$zshenv" <<EOF

$sentinel_begin
# Claude Code — subscription OAuth token loaded from 1P at shell start.
# In .zshenv (not .zshrc) so non-interactive subshells (e.g. spawned by
# Claude Code Desktop's Bash tool) also pick it up.
# Token rotates yearly via \`claude setup-token\`.
if [[ -z "\$CLAUDE_CODE_OAUTH_TOKEN" ]] && command -v op >/dev/null 2>&1; then
  export CLAUDE_CODE_OAUTH_TOKEN="\$(op read 'op://pax-cloud-secrets/Claude Code OAuth Token/credential' 2>/dev/null)"
fi
$sentinel_end
EOF
    ok "added CLAUDE_CODE_OAUTH_TOKEN loader to ~/.zshenv"
  fi
  note "Open a new terminal (or 'source ~/.zshenv') to pick up the env var"
}

# ────────────────────────────────────────────────────────────────────
# Phase 7: MCP server packages + launcher scripts + claude mcp add
# ────────────────────────────────────────────────────────────────────
phase_7_mcps() {
  log "Phase 7 — MCP servers"
  local mcp_pkgs="@notionhq/notion-mcp-server @xeroapi/xero-mcp-server @modelcontextprotocol/server-slack @modelcontextprotocol/server-gdrive"
  for pkg in $mcp_pkgs; do
    npm install -g "$pkg" >/dev/null 2>&1
    ok "installed $pkg"
  done

  # Mac-flavoured launchers — uses op via desktop 1P CLI integration, no /srv path
  local mac_launcher_dir="$HOME/.pax-mcp-launchers"
  mkdir -p "$mac_launcher_dir"

  for svc in notion xero slack; do
    cat > "$mac_launcher_dir/$svc.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
EOF
  done

  cat >> "$mac_launcher_dir/notion.sh" <<'EOF'
export NOTION_TOKEN="$(op read 'op://pax-cloud-secrets/Notion PAT - pax-cloud/credential')"
exec notion-mcp-server
EOF

  cat >> "$mac_launcher_dir/xero.sh" <<'EOF'
export XERO_CLIENT_ID="$(op read 'op://pax-cloud-secrets/Xero Custom Connection - pax-cloud/client_id')"
export XERO_CLIENT_SECRET="$(op read 'op://pax-cloud-secrets/Xero Custom Connection - pax-cloud/client_secret')"
exec xero-mcp-server
EOF

  cat >> "$mac_launcher_dir/slack.sh" <<'EOF'
export SLACK_BOT_TOKEN="$(op read 'op://pax-cloud-secrets/Slack Bot Token - pax-cloud/credential')"
export SLACK_TEAM_ID="$(op read 'op://pax-cloud-secrets/Slack Bot Token - pax-cloud/team_id')"
exec mcp-server-slack
EOF

  cat > "$mac_launcher_dir/gdrive.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
export GDRIVE_OAUTH_PATH="$HOME/.gdrive-auth/gcp-oauth.keys.json"
export GDRIVE_CREDENTIALS_PATH="$HOME/.gdrive-auth/.gdrive-server-credentials.json"
exec mcp-server-gdrive
EOF

  chmod +x "$mac_launcher_dir"/*.sh
  ok "wrote Mac-flavoured MCP launchers to $mac_launcher_dir"

  # Register with claude
  for svc in notion xero slack gdrive; do
    if claude mcp list 2>/dev/null | grep -q "^$svc:"; then
      ok "claude mcp '$svc' already registered"
    else
      claude mcp add "$svc" -s user "$mac_launcher_dir/$svc.sh"
      ok "claude mcp '$svc' registered"
    fi
  done
}

# ────────────────────────────────────────────────────────────────────
# Phase 8: Drive OAuth keys (manual — keys exist in 1P; refresh tokens fresh on Mac)
# ────────────────────────────────────────────────────────────────────
phase_8_gdrive_auth() {
  log "Phase 8 — Drive OAuth keys"
  mkdir -p "$HOME/.gdrive-auth"; chmod 700 "$HOME/.gdrive-auth"

  if [ -f "$HOME/.gdrive-auth/gcp-oauth.keys.json" ]; then
    ok "gcp-oauth.keys.json already present"
  else
    if op vault list >/dev/null 2>&1; then
      op document get "Google Drive OAuth Keys - pax-cloud" --vault="${OP_VAULT}" --output "$HOME/.gdrive-auth/gcp-oauth.keys.json" 2>/dev/null && \
        ok "restored gcp-oauth.keys.json from 1P" || \
        warn "could not auto-restore Drive OAuth keys from 1P; restore manually if needed"
    fi
  fi

  if [ ! -f "$HOME/.gdrive-auth/.gdrive-server-credentials.json" ]; then
    note "Drive refresh tokens NOT restored (intentional — laptop refresh token was for the retired listener bot)."
    note "Run 'mcp-server-gdrive auth' once to generate fresh credentials (will open browser)."
  fi
}

# ────────────────────────────────────────────────────────────────────
# Phase 9: Verify droplet reachability
# ────────────────────────────────────────────────────────────────────
phase_9_droplet() {
  log "Phase 9 — verify droplet reachable"
  if ssh -o ConnectTimeout=5 -o BatchMode=yes pax-cloud-droplet echo ok 2>/dev/null; then
    ok "ssh pax-cloud-droplet works"
  else
    warn "Cannot SSH to droplet yet. Add the mac_mini_droplet public key to /home/pax/.ssh/authorized_keys on the droplet, then re-run."
    note "Suggested (run from a machine that already has droplet access):"
    note "  ssh root@${DROPLET_HOST} \"echo '$(cat ~/.ssh/mac_mini_droplet.pub)' >> /home/pax/.ssh/authorized_keys\""
    note "Or via DigitalOcean web console root access."
  fi
}

# ────────────────────────────────────────────────────────────────────
# Phase 10: Configure ~/.claude/settings.json with SessionStart/Stop hooks
# ────────────────────────────────────────────────────────────────────
phase_10_claude_hooks() {
  log "Phase 10 — Claude Code SessionStart/Stop hooks"
  local settings="$HOME/.claude/settings.json"
  mkdir -p "$(dirname "$settings")"

  if [ -f "$settings" ] && grep -q "mac-mini-pull-on-start" "$settings"; then
    ok "Mac Mini hooks already in $settings"
    return
  fi

  if [ -f "$settings" ]; then
    note "Backing up existing settings.json → settings.json.pre-mac-mini.bak"
    cp "$settings" "$settings.pre-mac-mini.bak"
  fi

  cat > "$settings" <<EOF
{
  "permissions": {
    "defaultMode": "bypassPermissions"
  },
  "theme": "dark",
  "agentPushNotifEnabled": true,
  "inputNeededNotifEnabled": true,
  "hooks": {
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash \$HOME/.openclaw/pax-memory/scripts/mac-mini-pull-on-start.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash \$HOME/.openclaw/pax-memory/scripts/mac-mini-sync-on-stop.sh"
          }
        ]
      }
    ]
  }
}
EOF
  ok "wrote $settings with SessionStart + Stop hooks pointing at pax-memory scripts"
  note "Verify in next Claude Code session: ~/.openclaw/pax-memory/agents/claudecode-macmini/sync.log should grow"
}

# ────────────────────────────────────────────────────────────────────
# Main
# ────────────────────────────────────────────────────────────────────
main() {
  log "Mac Mini bootstrap starting"
  phase_1_brew
  phase_0_op_signin
  phase_2_claude_code
  phase_3_ssh_keys
  phase_4_gh_auth
  phase_5_clone_repos
  phase_5b_pax_memory
  phase_6_claude_oauth
  phase_7_mcps
  phase_8_gdrive_auth
  phase_9_droplet
  phase_10_claude_hooks

  log "Bootstrap complete"
  echo ""
  echo "Next steps:"
  echo "  1. Source your shell or open a new terminal: source ~/.zshrc"
  echo "  2. Test: 'claude -p \"hello\"' should work under your subscription"
  echo "  3. Test: 'ssh pax-cloud-droplet hostname' should return the droplet hostname"
  echo "     If not, add ~/.ssh/mac_mini_droplet.pub to the droplet (see Phase 9 hint)"
  echo "  4. Open Claude Code app, start a session — check ~/.openclaw/pax-memory/agents/claudecode-macmini/sync.log"
  echo "     for a 'session start' entry confirming hooks fire"
  echo "  5. Verify pax-memory updates from this machine push correctly:"
  echo "       touch ~/.openclaw/pax-memory/agents/claudecode-macmini/last-seen.md"
  echo "       cd ~/.openclaw/pax-memory && git diff && git add . && git commit -m 'test from mac-mini' && git push"
  echo ""
  echo "When everything is green and you've run on Mac Mini for ≥48h alongside the laptop, plan the Windows reformat."
}

main "$@"
