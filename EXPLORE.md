# Ideas to explore

What remains after version 0.3.0 (since 0.2.3: `Offset#predict`,
the reading expected at a reference, `Knowledge#offset`, `#shift`
and `#track`, `Track#foresee`; since 0.2.2: a column constant
within rounding, a Quantity with `cusum_h` below 4 `cusum_k` refused,
a robust crawl taken through at once, Quantity and Setup through
Marshal; since 0.2.1: the return test
reading a block mean within ±(h/2 − k), a reference's pinned track
left out of its σ in the Fusion, Student-t reweighting until it
settles, Dynamics steps and forecasts free of a Mode, regimes asked of
local times, and nine smaller fixes, each with its test; since 0.1.2:
the Tracker by blocks
of three hours, an Offset's widths as the held-out bins confirm them,
the keep rule on the correction, two parts fused by inverse variance
with their σ widened by their gap, the block under way counted for its
share, a jump that clears the way it came, a reference judged with its
room's width, a sensor judged against its reference alone, no suspect
below three, no lone-reading jump against a single other, a sole
reference's σ from its collocation, the Tracker's widths in the
correction's space, no witness, no model aging in the Fusion).
Ranked by the gain expected. Items 1 to 7 are this gem's; item 8
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
   correction until the next relearn drops it, or the Tracker flags
   the part. The cause is the gap r − neighbour leaving the range it
   was fitted on, not k's size: the neighbour's own level moves (the
   downstairs Airzone's, under-the-sink, about 4 °C lower from 1
   February: every bin of the month outside the fit, −3.0 °C of bias
   on its prediction), or the season reverses the gap, or a one-month
   fit. On the year, walk-forward, 13 of 34 neighbour terms predicted
   worse than the plain offset; the neighbours of every losing term
   are lone sensors with no track, so nothing tells their move. No
   learning-time rule (a cap on k, k stable across halves or months,
   refusing a term the held-out tenth did not confirm as a gap)
   refused the losers without refusing winners. Clamping the gap to
   the range fitted helps `predict` alone (0.885 against 1.050 °C)
   but nothing once blended with `Recent` (0.681 against 0.683), and
   is neutral to slightly worse for the Fusion (left-out RMS 0.296 to
   0.301), where the Tracker removes a broken part within about 36 h.
   Worth watching in production.
6. **Two sensors left without their reference** still stand still
   until a relearn, a reset or a jump clearing: their disagreement
   cannot be put on either. The witness that could move them is gone
   (DESIGN.md, Tracking: no var(z) gain).

7. **Regressions beyond the gas.** Untried: the aircon's energy room by
   room (the outdoor unit's meter against each room's Mode as a Switch
   per location), where the rooms' units run together as the valves
   open together, so pooled first; a heat pump's COP against the
   outside, which needs the heat delivered, no meter of which exists;
   a daily bin aligned to local days, if a source cannot stamp its
   days at noon.

## On the users' side

8. **Around sensorium 0.3.0:**
   - The API changed: a `Tracker` is made without `dynamics:`,
     `Tracker#update` and `Tick#call` take no `previous:`, and a
     `Fusion` is made without `dynamics:`; `collocations:` is new to
     the `Fusion`, optional (a sole reference's σ). A `Knowledge` from
     a store carries the collocations already. Since 0.2.1, a
     `Parts::Part` carries the reading's `time`, `Offset#correct` takes
     `held:` (whether a Mode holds), and a store learned with two
     Modes holding at once keeps Shifts named by both (`aircon+fan`,
     `cooling+on`). Since 0.2.2: `Stats.constant?` (a column that
     does not vary has no slope); `Transient::DIGITS` and
     `Transient.canonical`, `.sides` and `.past` (changes compared at
     nine decimals); `Influence::Switch::OFF` (the texts that say
     off); `Dynamics::Forecast.new` takes an optional fourth argument,
     `near`; `Setup#with` and `Quantity#with` derive again what was
     not given; and a regime is asked of local times, so a regime of
     one's own sees the History's zone. Since 0.2.3: a `Quantity`
     with `cusum_h` below 4 `cusum_k` raises ArgumentError; a
     `Quantity` and a `Setup` round-trip through Marshal, and two
     `Regime::Calendar` of the same months are equal. Since 0.3.0:
     `Offset#predict`, `Knowledge#offset`, `#shift` and `#track`, and
     `Track#foresee` (README, Predicting), for ClimatControl, which
     opens MadHouse's store read-only (`read_only: true`, a SELECT-only
     user) and pins the tag; a `Store::Sequel` opened `read_only: true`
     raises `Store::ReadOnlyError` on any write. After 0.3.0:
     `Sensorium::Recent` (`learn`, `find`, `named`, `#predict`), the
     gap of the last 3 days, computed by the caller (README,
     Predicting); `Offset#predict` and `#correct` raise ArgumentError
     on a Shift given with `held: false`. Since 0.4.0: `Regression`
     (`learn`, `load`, `#predict`, `#contributions`, `#follow`), the
     store's `regressions`, `keep_regressions`, `regression_tracks`,
     `keep_regression_tracks` and `forget_regression` and their two
     tables, `Setup#joint`, `#ridge` and `#nonnegative`,
     `Influence::Series#weighted`, `Timeline.of`, `#on_of` and
     `#levels_of`, `Series#of(total:)`, `#sums`, `#added` and
     `#weighted`, `Stats.least_squares(ridge:)` and `Stats.nonnegative`
     (README, Regressions and Toolkit), for ClimatControl's gas
     baseline. Two changes an existing caller may meet: `keep_tracks`
     raises ArgumentError on a track of another quantity than the one
     it is kept under (the two stores filed it apart), and an
     `Offset::Moment` takes a Symbol name as its String (a Series'
     value or an exposure so named was taken as unknown).
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
  reference jumps on the year);
- against a neighbour term that breaks: k stable across halves or
  months, refusing terms the held-out tenth did not confirm as a gap,
  refusing every k above 0, clamping the gap to the range fitted
  (DESIGN.md, Ruled out);
- a Series on a valve's power as a heating-effort term (refused
  everywhere; forced in, it over-corrected);
- a table of Recent gaps learned on a schedule (a day stale, 4.6 %
  worse than computing it when asked).
