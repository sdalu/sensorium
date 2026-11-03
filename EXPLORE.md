# Ideas to explore

What remains after version 0.2.1 (since 0.1.2: the Tracker by blocks
of three hours, an Offset's widths as the held-out bins confirm them,
the keep rule on the correction, two parts fused by inverse variance
with their σ widened by their gap, the block under way counted for its
share, a jump that clears the way it came, a reference judged with its
room's width, a sensor judged against its reference alone, no suspect
below three, no lone-reading jump against a single other, a sole
reference's σ from its collocation, the Tracker's widths in the
correction's space, no witness, no model aging in the Fusion).
Ranked by the gain expected. Items 1 to 6 are this gem's; item 7
belongs to its users, MadHouse and ClimatControl.

The evidence comes from two sources: a room recorded over 30 winter days
(learned on the first 20, scored on the last 10), and MadHouse's year
2025-10-31 to 2026-10-31, replayed walk-forward (relearned each month,
a Tick every ten minutes), read-only.

## Worth doing next

1. **A fresh track starting on a bias.** Four of the year's false jumps
   came within hours of a relearn, the two-month fit not knowing a bias
   standing that week (−0.3 to −0.9 °C). A track's prior from the
   Offset's width absorbed the real steps too; the cause is in the
   Learner (weight the recent weeks in the constant), not the Tracker.
2. **The downstairs Airzone's spikes.** A σ 0.7–1.4 unit that reads
   +1.5 to +3.4 °C for 3 to 6 hours: flagged in two or three blocks,
   cleared one to five days later. A cause of its own; its own
   transient profile is the first thing to try.

## Smaller

3. **The delta held at a jump** is the one at the jump, which has taken
   in part of a step during the detection delay: a part whose step was
   real, then undone, may not clear. A field for the delta at the start
   of the flagged run (a store column) would fix it.
4. **Blame in a room whose third sensor is noisy**: a step between the
   two tight ones is put on either by noise (October on the year: the
   reference flagged for the tado's step).
5. **A neighbour with k above 0 that breaks mid-season** leaves a biased
   correction until the next relearn drops it (once on the year:
   downstairs Airzone, early February, 2.5 σ for a fortnight). No
   principled cap helped; worth watching in production.
6. **Two sensors left without their reference** still stand still
   until a relearn, a reset or a jump clearing: their disagreement
   cannot be put on either. The witness that could move them is gone
   (DESIGN.md, Tracking: no var(z) gain).

## On the users' side

7. **Around sensorium 0.2.1:**
   - The API changed: a `Tracker` is made without `dynamics:`,
     `Tracker#update` and `Tick#call` take no `previous:`, and a
     `Fusion` is made without `dynamics:`; `collocations:` is new to
     the `Fusion`, optional (a sole reference's σ). A `Knowledge` from
     a store carries the collocations already. Since 0.2.1, a
     `Parts::Part` carries the reading's `time`, `Offset#correct` takes
     `held:` (whether a Mode holds), and a store learned with two
     Modes holding at once keeps Shifts named by both (`aircon+fan`,
     `cooling+on`).
   - MadHouse's tables need the five columns added in 0.2.0 if it opens
     the store with `migrate: false`: `block_share` on offsets;
     `block_sum`, `block_noise`, `block_count` and `block_at` on tracks.
   - `climat sensors read` and the planner should be checked against the
     wider σ values.

## Tried and dropped

So that nobody tries them again; the reasons are in brackets or in
DESIGN.md, but for quantisation handling, despiking, other bin widths,
a GLR test and robust Kalman updates, whose reasons no document
records:

- splitting the mid regime into spring and autumn; raising the 80 % keep
  threshold; keeping every confirmed term at the refit; a held-out test
  by day or by forward folds (on the year, none gained beyond its
  spread);
- a cap on a neighbour's k;
- the heating as a delayed, filtered Series; PV power for the daily
  cycle (refused by the learner on almost every sensor, no gain forced
  in);
- two parts without the widening; one Student-t step at every size;
- the dynamics witness with the outside series, as learned now (no
  gain once a sensor is judged against its reference alone);
- judging a sensor against its reference alone only in rooms that
  normally have three (the same pair knows the same thing); letting a
  suspect count where leaving it out leaves one other (the leak the
  suspect rule exists against);
- a fresh track's prior from the Offset's width (absorbed both real
  steps); the Detector's skip of transients alone;
- scaling each innovation by its long-run variance (blinds the
  detector); prewhitening the innovations;
- counting `min_part` in independent bins;
- learning on fresh bins only (the correlation is the room's, not the
  carry's);
- quantisation handling, despiking, other bin widths;
- lag terms (`valve-1` lags about 5 min, which nothing narrows);
- a complementary filter or weights by time scale (the inverse-variance
  fusion is already at the optimum);
- change-point segmentation (the one level change was the weather);
- `track_q` estimated from the innovations (they are never white);
- a GLR test, robust (Huber) Kalman updates;
- holding a suspect's delta (turns a real bias into a jump);
- taking the reference's collocation σ out of each sensor's σ (the
  downstairs sensors' shared errors put on the reference, a real July
  step on the tado unflagged);
- carrying a track across a relearn (false jumps 30 to 34);
- judging the reference by its own σ in the Tracker (two false
  reference jumps on the year).
