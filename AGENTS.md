# mac-mini-bootstrap — Project Context

Idempotent bootstrap script + launchd plists to turn a fresh Mac Mini into the new local-node half of Jai's Pax stack. Replaces the Windows laptop per `pax-memory/projects/mac-mini-laptop-transition.md`.

- **Owner:** Jai Aguilar (jai@flowautobody.com.au)
- **Production URL:** n/a (one-time bootstrap on fresh Mac)
- **Repo:** https://github.com/jaiaguilar-alt/mac-mini-bootstrap
- **Infra:** bash script (`scripts/bootstrap.sh`) + `launchd` plists for listeners that need to survive reboot.

---

## At the start of every session

1. Read this file.
2. Read `README.md` for the full bootstrap flow + pre-bootstrap manual steps.
3. Read `pax-memory/projects/mac-mini-laptop-transition.md` for transition context (what's moving from the Windows laptop, what's retiring).
4. Read `pax-memory/projects/pax-architecture.md` for the broader stack diagram (Mac Mini is the local-node half; droplet is the cloud half; both stay).

## Secrets

- Reads everything from 1Password via `op` CLI. **No secrets in this repo.**
- 1P paths referenced: `op://pax-cloud-secrets/GitHub PAT - pax-cloud/credential`, `op://pax-cloud-secrets/Claude Code OAuth Token/credential`, and others documented in `scripts/bootstrap.sh` per phase.
- Bootstrap will fail loudly at Phase 0 if `op vault list` doesn't return a vault list. That's the gate.

## End-of-turn logging

Standard. README's "What `bootstrap.sh` does" table is the source of truth for what each phase does; keep it in sync with the script. Substantive changes get a line in `pax-memory/projects/mac-mini-laptop-transition.md`.

## How Jai works (style)

- Plain language, concrete analogies.
- Bite-size, brief.
- Scripts are addressed to a future Jai or another agent running this cold on a fresh machine — no implicit context.

## Project-specific

- **Idempotent.** Every phase must be safe to re-run. If a phase asks "are you sure?" before a destructive step, that's by design.
- **macOS only.** Apple Silicon or Intel. Won't run on Linux / Windows.
- **Pre-bootstrap manual steps are non-negotiable** — 1Password CLI integration in particular gates the whole flow. Don't try to automate around it.
- **Mac Mini provisioning order** matches `pax-memory/projects/mac-mini-laptop-transition.md` "Mac Mini provisioning order" section. Bootstrap implements that order in script form.
- **Companion to pax-backup (archived).** The Windows-era backup utility is reference; bootstrap does not invoke it.
