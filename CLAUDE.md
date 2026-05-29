<!-- Project-scoped config for the ruflo-machine-ref kit. The machine-wide ruflo + agentic-qe
     reference (operating rules, agent coordination, swarm/routing, the full ruflo CLI surface)
     lives in the global ~/.claude/CLAUDE.md — do NOT duplicate it here; defer to it. -->

# ruflo-machine-ref — project notes

This repo **is** the kit that installs/repairs ruflo + agentic-qe machine-wide. It is not a
typical app — it's a set of Bash + Node (ESM) helpers plus a managed block that gets merged
into the global `~/.claude/CLAUDE.md`. Anything generic (rules, SendMessage coordination,
swarm defaults, the ruflo CLI reference) is in the **global** `~/.claude/CLAUDE.md`; this file
holds only what's specific to developing *this* repo.

## Layout

| Path | What it is |
|------|------------|
| `bin/` | Standalone helpers (`ruflo-enable-learning`, `ruflo-patch-native`, `ruflo-improvement-eval`, …). Each sources `ruflo-lib.sh` and supports `--help`. |
| `shell/ruflo-functions.sh` | Shell functions sourced into the user's rc (`ruflo-resync`, `ruflo-onboard`, `ruflo-reference-refresh`, …). |
| `shell/ruflo-lib.sh` | Shared helpers (colors, `run`/`have`, daemon parser, native-better-sqlite3 primitives). Deployed to `~/.config/ruflo/` so `bin/` scripts can source it from a stable path. |
| `claude/ruflo-reference.md` | The machine-wide reference block. `install.sh` stages it to `~/.config/ruflo/claude-md-template.md` and merges it into `~/.claude/CLAUDE.md` between `<!-- BEGIN/END ruflo-reference -->` sentinels. |
| `install.sh` / `uninstall.sh` | Entry points (idempotent; honor `DRY=1`). |
| `docs/` | `BACKGROUND.md`, `TROUBLESHOOTING.md`, `upstream/` (findings filed upstream), `superpowers/{plans,specs}/` (dated design records — keep as history). |

## Build & test (there is no build system)

No `package.json`, no Makefile, no CI. Validate changes with:

```bash
bash -n shell/*.sh bin/<script>          # syntax-check shell
node --check bin/<node-script>           # syntax-check node (ESM) helpers
bin/<script> --help                      # smoke-test the help/usage path
bin/ruflo-parity-test                    # cross-shell/native parity checks
```

Run the relevant helper end-to-end against a scratch dir when it mutates state (most write to
`/tmp` or take a target path). `ruflo --version`-gate anything that patches the global install.

## Conventions

- **Defer to global, don't duplicate.** If guidance is generic ruflo/agentic-qe behavior, it
  belongs in `claude/ruflo-reference.md` (→ global), not here.
- **Dogfooding artifacts are not source.** Running `ruflo init`/`aqe init`/`ruflo-onboard`
  against this repo writes `.agentic-qe/`, `.claude/`, `*.db`, and `CLAUDE.md.{backup,pre-ruflo}`
  — all gitignored. Never commit them.
- **Patches to the global ruflo/agentic-qe dist must be version-gated and idempotent**, with a
  clear no-op + message once the fix is upstream (see `bin/ruflo-patch-route-learning`).
- **Commit attribution:** no `Co-Authored-By` trailer unless `.claude/settings.json` sets
  `attribution.commit` (per the global rule).
- Design work lands as a dated plan + spec under `docs/superpowers/`; supersede rather than
  delete, so the history of *where we've been* stays legible.
