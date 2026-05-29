# ruflo self-improvement: findings & upstream issue

This documents what we learned investigating whether ruflo is *self-improving* (not just
self-learning), the fix we shipped, and a ready-to-file upstream issue. Plain-language
primer first; evidence and the issue text follow.

## Plain-language primer (no ML background needed)

Picture a **delivery company**. ruflo has *three different* learning systems people conflate:

1. **The Q-learner = the dispatcher** — "which specialist handles this task?" It keeps a
   scorecard of which agent does well on which task and updates it from results.
   - **ε (epsilon)**: how often it gambles on a random pick vs its favorite (1.0 = all
     guessing; should shrink as it learns).
   - **TD error (δ)**: "how surprised it was" — shrinks toward 0 as it converges.
   - **|Q|**: how many task-types it has opinions about.
2. **SONA = a driver's muscle memory** — nudges itself after each action; banks
   *trajectories* and *patterns*.
3. **LoRA = the *format* SONA stores tweaks in** — a small "diff sheet" of corrections on a
   frozen base. **Δ LoRA** = how big the last tweak was.

**Self-learning** (banking experience) vs **self-improving** (using it to get measurably
better) are different claims. ruflo is clearly self-learning. Whether it's self-improving
required digging.

## Findings (verified against ruflo 3.10.5 source + experiment)

### F1 — The route Q-learner *does* learn (in-process)
ruflo's `createQLearningRouter` genuinely learns: 200 in-process updates → Q-table grows,
ε decays (1.0→0.91), TD error nonzero. The algorithm works.

### F2 — CLI `route feedback` cannot persist (BUG — we fixed it)
`route.js` `feedbackCommand` calls `update()` but **never `saveModel()`**, and
`q-learning-router.js` defaults `autoSaveInterval: 100`. Each CLI call is a fresh process
that loads the model, applies **one** update, and exits before the %100 auto-save triggers —
so the persisted model never advances and `route stats` is permanently `Update Count 0 /
ε 1.0`. **The route learner therefore never learns from real CLI use.**
*Fix (shipped as `ruflo-patch-route-learning`):* set `autoSaveInterval: 1`. Validated — six
separate CLI `route feedback` calls then accumulate (Update Count 0→6, ε 1.0→0.997, model
persisted).

### F3 — The state encoder collapses semantically-distinct tasks
`featureVectorToKey` keys largely on length/word-count buckets; tasks with different routing
keywords but similar shape hash to the **same** Q-state (verified: six keyword-distinct
tasks → 1 state). So even with F2 fixed, the router can't represent task-specific routing
well — distinct tasks share a policy slot.

### F4 — The matrix-LoRA / SONA path is never consumed at inference (Tier-2 gap)
Every `SonaCoordinator` call in ruflo is training/recording (`recordSignal`,
`recordTrajectory`, `endTrajectory`, `distillLearning`); the coordinator exposes **no
inference method** (`predict`/`forward`), and the matrix-LoRA `forward_array` has **zero
callers** outside its own training file. The "LoRA" in `intelligence.js` is a scalar
per-pattern confidence nudge merely *named* "LoRA-style". So the trained LoRA (the climbing
`Δ LoRA`/`B.sumAbs`) **changes no decision** — it's written, never read. Consuming it is
upstream R&D (adding an inference path to a native/WASM package), not a kit patch.

### F5 — With F2 fixed, the route learner self-improves — significantly but modestly
Our held-out, ablated, multi-seed experiment (`ruflo-improvement-eval`) over a synthetic
environment engineered to occupy distinct Q-states (per F3) shows the learner beats a
no-learning ablation with a **statistically significant, monotone** gain — but a **modest**
one (it learns the optimal action for only part of the state space within practical episode
counts, plateauing well below 100%). Honest verdict: **self-improving = yes (proven for the
consumed loop), but weak.**

```
route Q-learner · 5 seeds · learning vs no-learning ablation
  cold 17% → warm 33%   Δ+16pp   permutation p=0.004   Cohen's d=∞   above-chance: yes
  (modest ceiling — partial learning; see F3 encoder collapse + slow ε decay)
```

## What this kit ships
- **`ruflo-patch-route-learning`** — fixes F2 (idempotent; re-run after each ruflo upgrade;
  wired into `ruflo-resync`).
- **`ruflo-improvement-eval`** — the held-out/ablated proof harness (F5); also the measuring
  stick for any future Tier-2 work.

## Ready-to-file upstream issue (ruvnet/ruflo)

> **Title:** Route Q-learner never persists CLI feedback; trained LoRA/SONA not consumed at inference
>
> **Body:**
> Two issues make ruflo's routing appear non-self-improving:
>
> **1. `route feedback` doesn't persist (CLI learning is a no-op).** `commands/route.js`
> `feedbackCommand` calls `router.update(...)` but never `router.saveModel()`, and
> `ruvector/q-learning-router.js` `DEFAULT_CONFIG.autoSaveInterval = 100`. Since each CLI
> invocation is a fresh process applying a single update, the `%100` auto-save never fires,
> so the persisted `.swarm/q-learning-model.json` never advances and `route stats` stays at
> `Update Count 0 / Epsilon 1.0` regardless of how much feedback is given. *Suggested fix:*
> call `await router.saveModel()` at the end of `feedbackCommand` (and/or set
> `autoSaveInterval: 1`).
>
> **2. Trained LoRA/SONA is never consumed at inference.** `SonaCoordinator` exposes only
> recording/training methods (no `predict`/`forward`); the MicroLoRA `forward_array` has no
> callers outside its training file. So trained adaptations (rising `deltaNorm`/`B.sumAbs`)
> don't influence any routing decision. *Suggested direction:* expose an inference path from
> the trained adapter and consume it in the routing/recall scorer, so learning closes the
> loop.
>
> **3. (Minor) State encoder collapses distinct tasks.** `featureVectorToKey` keys largely on
> length/word-count buckets; routing-keyword-distinct tasks collide to one state, limiting
> task-specific routing.
>
> Environment: ruflo 3.10.5, Node 26. Repro scripts: `ruflo-improvement-eval`,
> `ruflo-patch-route-learning` (https://github.com/pacphi/ruflo-machine-ref).
