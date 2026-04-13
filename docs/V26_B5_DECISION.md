## Chosen Option

**Option A: Stay with SmolLM-135M v5/v6.**

## Justification

SmolLM-135M v5/v6 is already working in production — boots to `nova>`, runs 14 LLM shell commands, generates tokens via `ask`. The V26 goal is "80% to 95% production" which means fixing bugs and hardening infrastructure, not adding new features. Upgrading to SmolLM-360M (Option B) would require 12h of export script adaptation, tensor pool extension to 1024-dim, and model loader changes — all for a quality improvement that is nice-to-have, not a production blocker. Option C (Gemma 270M) at ~40h is clearly out of scope for V26.

The remaining V26 budget is better spent on VFS write paths (B3), KASLR (B4.5), and CI hardening — these directly improve production readiness. LLM quality upgrade is deferred to V27 where it can be the primary focus with a dedicated 2-week sprint.

Phase B actual effort has been running 75-90% under estimate (B0-B4 total ~11h actual vs ~45h estimated). The surplus should go to closing B3 (VFS) and B4.5 (KASLR), not expanding scope into B5.

## Rollback Plan

Option A requires no rollback — it preserves the status quo. If V27 decides to upgrade to SmolLM-360M or Gemma 270M, the existing v5/v6 infrastructure remains as a working baseline. The tensor pool, model loader, and inference pipeline are all designed to be model-agnostic; upgrading only requires new export scripts and dimension constants, not architectural changes.

## Timestamp and Signature

**Decision by:** Muhamad Fajar Putranto
**Date:** 2026-04-14
**Plan reference:** `fajar-lang/docs/V26_PRODUCTION_PLAN.md` Section B5.0
**Hygiene rule:** Plan Hygiene Rule 6 (decisions must be committed files)
