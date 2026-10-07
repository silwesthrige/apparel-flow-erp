# AI Assistance Log (working notes → AI_OPTIMIZATION_REPORT.md)

Record each time AI output was wrong, insecure, or sub-optimal, as it happens.
Format: what the AI produced → why it was wrong → what I changed → where.

## Day 1 — Schema & setup

### 1. State machine skipped `CUTTING_IN_PROGRESS`
- **AI output:** First schema draft defaulted `cutting_orders.status` to `PENDING_VERIFICATION`.
- **Problem:** The spec's state diagram starts at `CUTTING IN-PROGRESS`, and rejected batches must return
  there for re-cutting. The default silently removed a state, so the reject loop had nowhere to go.
- **Fix:** Default is `CUTTING_IN_PROGRESS`; the transition trigger only allows
  `CIP → PENDING → (VERIFIED | REJECTED)`, `REJECTED → CIP`, `VERIFIED → IN_SEWING`.
- **Where:** `lib/db/schema.ts`, `drizzle/0001_integrity_triggers.sql`

### 2. Starter template caused white-on-white inputs (pre-existing, caught before UI work)
- **Output:** `create-next-app`'s `globals.css` set `--foreground: #ededed` under
  `prefers-color-scheme: dark`, while native inputs keep a white background.
- **Problem:** On a dark-mode OS, input text is near-invisible: the exact UAT defect in the brief.
- **Fix:** Light-only palette with `color-scheme: light`, explicit text and background colours on
  `input/select/textarea/option`, a placeholder colour with a 4.76:1 contrast ratio, and a visible focus ring.
- **Where:** `app/globals.css`

### Verified by experiment (not trusted on sight)
Ran migrations in PGlite and attempted 21 operations: skipping states, verifying a RED batch,
forging the generated `status` column, editing wastage after verification, editing/truncating logs,
deleting orders. Every illegal one was rejected by Postgres.
