---
name: ruflo-token-audit
description: "Use when the user is burning through Claude usage/tokens unexpectedly fast, hitting plan limits, or asks 'where are my tokens going' / 'why is my usage so high'. Audits local Claude Code session transcripts across the past N days, distinguishes interactive use from runaway automation (background daemons, swarms, hooks), and recommends concrete fixes."
user-invocable: true
---

# Ruflo Token Audit

Diagnose unexpectedly high Claude Code token/usage consumption by analyzing the local
session transcripts in `~/.claude/projects/**/*.jsonl` (every assistant message records
its token usage). The goal: tell the user **whether their burn is interactive work or
background automation**, and give them concrete levers.

## When to use

Trigger on: "I'm burning tokens too fast", "hitting my Max/Pro limit in a day or two",
"where are my tokens going", "why is my usage so high", "is the plan worth it". Also
proactively if the user mentions surprising usage.

## Procedure

1. **Run the engine** (ships with the ruflo-machine-ref kit, on PATH as
   `ruflo-token-audit`):
   ```bash
   ruflo-token-audit --days 7
   ```
   - Honor any window the user gives ("past two weeks" → `--days 14`).
   - If the command is not found, the kit's `bin/` isn't on PATH; fall back to running
     the script directly from the repo (`python3 bin/ruflo-token-audit`) or tell the user
     to add `~/.local/bin` to PATH.
   - Use `--json` if you need to compute follow-ups; otherwise the human report is enough.

2. **Read the signals — interactive vs automation.** The report is built to answer one
   question. Interpret it, don't just echo it:
   | Signal | Interactive | Automation leak |
   |---|---|---|
   | Sessions/day | tens | hundreds–thousands (one/minute = robotic) |
   | Dominant model | Opus | Haiku/Sonnet (swarm subagents/workers) |
   | Tiny sessions (<200K) | low % | high % (hooks/workers/subagents) |
   | Sessions-per-project | varied | several projects at near-identical high counts |
   | Running daemons | none | one+ `ruflo daemon start`, often mapped to top-burn projects |

3. **Check the daemon cross-reference** (the most common root cause). The report's
   "RUNNING ruflo/claude-flow DAEMONS" section lists live `daemon start` processes and
   flags any whose workspace is a top-burn project. Each daemon spawns worker sessions
   continuously and is **invisible to `ruflo daemon status`** (that only checks the
   current workspace). If daemons are listed:
   ```bash
   ruflo-daemon-gc            # preview stale daemons
   ruflo-daemon-gc --kill     # stop them
   ```
   Confirm authorization before killing, then verify with another `ruflo-token-audit`.

4. **Note the startup context tax.** "STARTUP CONTEXT TAX" is the fixed per-session cost
   (system prompt + tool/skill manifests + CLAUDE.md, loaded before any work). A large
   median × many sessions compounds. Levers: trim oversized global/project `CLAUDE.md`,
   reduce always-loaded MCP tool defs (~84k tokens/session for a heavy MCP).

5. **Report like a diagnosis, not a data dump.** Lead with the verdict (interactive vs
   automation, and the single biggest driver). Then the supporting numbers (a small
   table), then ranked, concrete fixes with the exact commands.

## Caveats (be honest)

- The cost-weight is an **Opus-equivalent reference** to compare line items — NOT the
  user's actual Max/Pro plan billing. Don't present it as dollars owed.
- High **cache-read** is normal and cheap; flag it only when it's huge *and* multiplied by
  thousands of automated sessions.
- A few hundred sessions from legitimate parallel subagent work is not a leak. The tell is
  *unattended, repeating* sessions (daemons/cron/loops) with little interactive Opus.

## Sample prompts the user can use

- "Audit my Claude Code token usage for the last 7 days — what's burning my tokens?"
- "I'm hitting my Max limit in a day. Run the token audit and tell me why."
- "Check for runaway ruflo daemons and show me my heaviest projects this week."

## Background

This skill was built after a real incident: six leaked `ruflo daemon start` processes
(one per onboarded project, oldest running 19 days) produced ~10,100 sessions / 8.1B
tokens in a week — ~94% background machinery vs ~6% interactive Opus. The kit now makes
the daemon opt-in and auto-reaps stale ones; this audit is how you catch a recurrence
(or any other automation leak).
