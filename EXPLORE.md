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
Ranked by the gain expected. Items 1 to 3 are this gem's; item 4
belongs to its users, MadHouse and ClimatControl.

The evidence comes from two sources: a room recorded over 30 winter days
(learned on the first 20, scored on the last 10), and MadHouse's year
2025-10-31 to 2026-10-31, replayed walk-forward (relearned each month,
a Tick every ten minutes), read-only.

## Smaller

1. **Blame in a room whose third sensor is noisy**: a step between the
   two tight ones is put on either by noise. At 0.5.0 and the
   recentred constant the October case is gone; red-room's reference
   is flagged twice in January (11th and 24th) for the tado's moves
   (tado − reference swung −1.26 °C, then +0.5 to +0.8, while Airzone −
   reference held near −0.3), cleared in about three days each. Once
   the reference is the suspect, the tado's only other truth is the
   noisy Airzone and it stands still. A suspect chosen by leave-one-out
   disagreement instead of the highest CUSUM did not help (DESIGN.md,
   Ruled out).
2. **A neighbour with k above 0 that breaks mid-season** leaves a biased
   correction until the next relearn drops it, or the Tracker flags
   the part. The cause is the gap r − neighbour leaving the range it
   was fitted on, not k's size: the neighbour's own level moves, or
   the season reverses the gap, or a one-month fit. On the year,
   walk-forward (relearned each month, at 0.5.0 and the recentred
   constant), 16 of 41 neighbour term-months predicted worse than the
   plain offset: 0.923 °C RMS against 0.840. Most of the loss is one
   neighbour, under-the-sink/kuang-si (its level about 4 °C lower
   from 1 February), taken by downstairs' Airzone with k 0.99, then
   0.76 (2.80 °C RMS in February against 1.12 plain). Learned with it
   not a neighbour (`Sensor#neighbour` false), the terms predict at
   0.766 °C, ahead of the plain offset, and the Fusion's left-out
   var(z) goes from 0.506 to 0.494 (downstairs' tado 0.451 to 0.397,
   its reference 0.535 to 0.459; every other part unchanged): MadHouse's
   to set (item 4). What breaks after that is smaller (corridor/nite-owl
   in August, 1.05 against 0.52; blue-room's tado on shower-room's
   reference in November, −0.84 °C with the valve closed). Refusing
   every lone neighbour (one with no Offset and no reference role, so
   no track) and the earlier learning-time rules and clamp are ruled
   out (DESIGN.md, Ruled out). Worth watching in production.
3. **Regressions beyond the gas.** Untried: the aircon's energy room by
   room (the outdoor unit's meter against each room's Mode as a Switch
   per location), where the rooms' units run together as the valves
   open together, so pooled first; a heat pump's COP against the
   outside, which needs the heat delivered, no meter of which exists;
   a daily bin aligned to local days, if a source cannot shift its
   times onto them (README, Regressions: GRDF's gas day).

## On the users' side

4. **Around sensorium 0.3.0:**
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
     value or an exposure so named was taken as unknown). Since
     0.5.0: a term is judged with the bins it acts on weighing as much
     as the others (`Fit::Balanced`), so a relearn may keep other terms:
     three of MadHouse's 32 tado offsets (green-room mid and winter,
     yellow-room winter); a Regression fitted together no longer stops
     at the first regressor the bins held out refuse.
     Since 0.5.1: an offset's constant is recentred on the last weeks
     (`Setup#recent`, a week by default; `nil` for the former
     constant), so a relearn moves constants toward the gap the last
     week held, and a part whose gap drifts with the season is jumped
     less after a relearn.
   - MadHouse: under-the-sink/kuang-si as a neighbour cost more than
     every other neighbour term gained (item 2). Done in MadHouse
     958f02e (2026-11-11): a named list of sensors no neighbour; its
     relearn moved bathroom's tado in summer to shower-room's
     reference, downstairs' Airzone having dropped kuang-si already
     with the recentred constant.
   - MadHouse: a room's reference goes silent for days (on the year,
     13 spells of 48 h or more, the longest 193 h, downstairs'), its
     two sensors' tracks standing still meanwhile (DESIGN.md, Ruled
     out). Done in MadHouse (2026-11-11, live, not yet committed): an
     alert once a reference has no reading for 6 h; and MadHouse pins
     v0.5.1 (f31707a).
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
- the valve's opening, capped at 50 %, as a location's Series: kept by
  blue-room's tado, no gain in the Fusion, and the gap per opening
  moved between last winter and November (DESIGN.md, Ruled out).
- a table of Recent gaps learned on a schedule (a day stale, 4.6 %
  worse than computing it when asked).
- half-lives of 3, 5 or 14 days for the recent constant (a week did
  best; DESIGN.md, Learning).
- the downstairs Airzone's spikes as an event of their own (its weight
  in the fusion about 1.5 %: 0.03 °C at most; DESIGN.md, Ruled out).
- the delta held at a jump taken where the flagged run started (on the
  year cleared 51 to 43, RMS 0.300 to 0.306; DESIGN.md, Ruled out).
- refusing every lone neighbour (no Offset, no reference role): on the
  year 0.814 against 0.923, but only through kuang-si; without it 0.796
  against 0.755 (DESIGN.md, Ruled out).

- the suspect chosen by leave-one-out disagreement (red-room's two
  misblames stayed; reference jumps 5 to 8; DESIGN.md, Ruled out).
- moving two sensors left without their reference (only their
  difference is seen; DESIGN.md, Ruled out).
