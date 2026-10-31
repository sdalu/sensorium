# Design

## Learning

- **Medians for the constant and the switch terms**, least squares
  only for the linear terms. A median shrugs off the minutes a door is
  open.
- **A term is kept when it narrows p10..p90 to 80 %**, both spreads
  measured over the bins the term covers. A spread between quantiles,
  not a variance, for the same reason as the medians; the same bins,
  or a neighbour covering fewer of them could win by leaving the rough
  ones out.
- **The gain and the neighbour fitted together** when both are kept.
  Both regress on the reference's level (r, and r − n), so fitted one
  after the other the second would be biased by the first. The one that
  narrows most alone goes first; the pair is kept only if it narrows
  that one again. The pair is fitted by least squares, not Deming:
  r carries the reference's error in both columns, and a two-column
  errors-in-variables fit needs the error covariance of r − n too,
  which nothing measures. A pair's gain is therefore biased toward
  zero by about σ²/var(r).
- **A greedy choice, then one joint refit.** Choosing terms one at a
  time keeps the choice simple and each step's test (the 80 %) honest,
  but a term fitted early takes in what a later one would explain
  where their regressors move together. Refitting the chosen terms
  together, by least squares, gives each its own share. The refit
  must leave no wider a spread than the greedy model over the same
  bins: the medians of the Switch terms shrug off rough bins that
  least squares would follow, and then the greedy model is the better
  one. It is done once, over the terms already chosen, not as a new
  search: a term that only narrowed by taking another's share stays
  in. A single term is not refitted: there is nothing to share, and a
  gain alone keeps its Deming line, which least squares would bias.
- **A gain alone is a Deming line.** Least squares of s − r on a noisy
  r biases the gain toward zero by about σ²/var(r), and within one
  regime var(r) is small. The gain is a Deming line of s on r, the
  variance ratio being what s's error is once r's (the quantity's σ)
  is taken out of the spread the line leaves, at least `floor`²,
  re-estimated until it settles. It is there for sensors wrong by a
  share (CO₂, light, particles); `Setup#gain` turns it off.
- **A scale floor on the linear terms.** A correction is (reading −
  the other terms + k × neighbour) / (1 + gain + k), and its σ is the
  spread over |1 + gain + k|. A sensor that mostly follows another
  place earns a k near −1: the term narrows the fit, but corrected
  back to r its noise is multiplied many times. A linear term, or the
  pair, that leaves |1 + gain + k| below `scale_floor` (0.5: at most a
  doubling) is refused where it would have been kept, and the Fit keeps
  the model before it; a less narrowing candidate is not tried in its
  place, for a sensor that follows another place more than its own is
  no estimate of its reference either.
- **Influences of four kinds.** A Switch is on or off (the radiators'
  water hot); with `tau:` its term follows a first-order filter of its
  on-state, since heat arrives and leaves gradually, the time constant
  chosen among those given as the one that narrows most. A Series is a
  level that moves the sensor in proportion (a PV inverter's power is a
  fair irradiance meter, and the sun is the largest error of an
  unshielded sensor). A Threshold is a Switch derived from the
  location's own reference (a capacitive humidity sensor reads high for
  hours after a humid spell). A Mode is left out, not modelled: what
  blown air does to a sensor depends on where it sits and how the air
  flows, not on any series there is; a Shift per value, over the plain
  offset, is all the data supports.
- **A term on the reference's rate.** Sensors with different time
  constants disagree on every transient by about τ·dr/dt. The term is
  the reference's own rate (per hour, a central difference over a bin
  each side), not a lagged copy of a series.
- **A spread per state.** What the model leaves is wider while a
  radiator runs by a sensor. The Fit keeps, for each Switch or
  Threshold kept as a term, the spread over the bins it was on, and the
  spread over the bins all of them were off, each over `min_part`
  bins. A reading takes the widest spread of the Switches on, so two
  influences at once are not counted as calm as either alone.
- **A spread per level for a Series**, above its median over the fit
  and not. A sensor in the sun is rougher the more it shines, but a
  spread per value would need more bins than a regime has; two halves
  split at the median each have half the fit's bins. The median is
  kept beside them, so a reading takes the half its value falls in.
  The Series' spread joins the Switches' in the widest-spread rule: a
  sunny bin with the radiators on is as rough as the rougher of the
  two.
- **A learning replaces what it learned again**, not whole regimes: the
  offsets of the sensors learned again, and of a location whose
  reference changed. A span that barely touches a regime, or a sensor
  short of samples this time, keeps a model that is still good. A
  sensor the source no longer lists is gone for good: its offsets go,
  in every regime, so they do not linger as notes on a device nobody
  reads.

## Transients

- **Learned per sensor, not a fixed rule.** How far a sensor moves in
  ten minutes depends on how it reports (a 0.1 °C step, a mean over
  five minutes, a radiator valve's sensor that follows the water), on
  where it sits and on the regime: a fall of 0.5 °C is an event on
  one and noise on another. Each sensor's changes over each window
  are its own yardstick, per regime, and the threshold is a z, the
  same for all.
- **σ from the median absolute deviation.** The changes a scale is
  learned from hold the very events it must tell apart: a variance
  would grow with every window opened, and the louder a sensor's
  events the less it would see them. The MAD ignores them while they
  are fewer than half; 1.4826 makes it a σ for a normal distribution.
  The median is taken out first, so a sensor that drifts steadily over
  a regime is not flagged for it.
- **Two scales.** A window opened cools the whole room: live, a
  sensor's own change says so, whatever its reference does. For
  learning only a sensor moving apart from its reference distorts its
  offset; a whole-room change (the radiators starting) moves both and
  leaves the gap alone. Hence the own scale for the Detector, the
  relative one for the influence, and none relative for a reference,
  which has no gap to itself.
- **Left out, not modelled**, as a Mode is: what an airing, a shower
  or a ray of sun does to a sensor depends on the moment (how wide the
  window, how cold outside, where the sun falls), not on any series
  the source tells; a term fitted to it would be noise. The bins are
  few, so leaving them out costs little, and a median already shrugs
  off rare ones; what it cannot shrug off is a sensor aired often, or
  in the sun every afternoon. No Shift either: a transient has no
  value to learn one per.
- **The Tracker stands aside during an event.** An opened window
  reads, to the CUSUM, as a step; a long one could push it past h and
  leave a track jumped until a relearn. The whole location is left as
  it was, as for a part with too few others: during a whole-room
  change the others' fusion is no truth either.

## Fusion

- **A shift applies over the plain offset**, the one it was learned
  over; the full model under a Mode would add a neighbour's term the
  shift never saw.
- **The reference is the moment's regime's**, so a location learned
  against another sensor in another regime keeps both models.
- **σ has a floor** (`Quantity#floor`): a spread learned at zero (a
  sensor reading in steps) would give one sensor all the weight.
- **Student-t reweighting, not a single drop.** Dropping the one part
  furthest from the others looks at one part at a time, so two sensors
  wrong together (the same radiator plume) could each pass while the
  pair pulled the value off. Reweighting every part by a Student-t
  factor on its own residual, iterated to convergence, downweights
  however many disagree, smoothly; when every part agrees the result
  is exactly the inverse-variance fusion.
- **A transform, not a humidity model.** Relative humidity depends on
  the sensor's own temperature; in absolute humidity the sensors'
  errors add up again, so the same learner and fusion apply. The
  context (temperature) travels with each reading, and the fused value
  is brought back at the location's fused temperature, which the caller
  gives.
- **Settings per quantity**: a smoke detector may be the temperature
  reference and not measure humidity at all, hence the humidity
  preset's own places (wall, valve).
- **Triple collocation measures; it does not feed the fusion.** It
  tells each series' own error apart, assuming the errors independent:
  an error every series shares is in no difference, and one shared by
  every series but one is put on that one. Fed to the fusion it moves
  the shared error from one σ to another rather than accounting for
  it, so it stays a measurement.

## Blending

- **Blending is not fusion.** Fusion estimates one location's truth
  from sensors that measure it; a blend says which locations matter,
  by a weight from outside (occupancy, area). Occupancy must not move
  a room's value, so it is a separate step over fused values, and it
  knows nothing of rooms: any keyed estimates, any weights.
- **In the quantity's own units**, from the values as they read: what
  the blend answers (the temperature where people are) is read in
  them.
- **Errors taken as independent**, so σ shrinks as the weight spreads
  over more estimates; locations sharing an error (one reference, one
  sun) make it optimistic, as it is for the fusion.

## Tracking

- **A scalar random-walk Kalman filter over the batch offset.** The
  batch learner keeps the structure; between two runs only the level is
  followed, as a delta on the Offset, which stays the prior (delta 0 on
  a fresh track or after a relearn). A random walk assumes no shape of
  drift; `track_q` bounds how fast the level may wander. The truth for
  a part is the others' fusion, the part left out, or it would pull its
  own truth; with fewer than two others a disagreement cannot be put on
  either side, so the part is left as it was, unless a witness stands
  in (below).
- **A slow filter, a CUSUM for jumps.** The gain is kept small so that
  noise does not move delta: a constant bias takes about a day to be
  learned at an hourly cadence. A step would then be absorbed over
  days, the value off all the while, so a two-sided CUSUM on the
  standardised innovations flags it (k = 0.5, h = 5, the textbook pair
  for a shift of one innovation σ). A slow ramp the filter keeps up
  with is said by the drift alarm instead (|delta| past 3 Offset σ,
  cleared under 2). A jumped track stays jumped until a relearn or a
  reset: the Tracker flags, a person or a relearn decides.
- **References tracked, but pinned.** A reference's reading is the
  location's definition of truth. Untracked, a reference that jumps
  makes every sensor beside it look jumped; tracked like the others,
  the deltas wander together and none learns a bias. So a reference
  runs the CUSUM and the jump state only, its delta pinned at 0.
- **References first, a jumped part out of the others.** A jumped part
  left in the others' fusion would pull them after it; within an
  update the references go first, and a part that has jumped is left
  out of every later part's others.
- **A witness from the location's own dynamics** for a part left with
  a single other, as in a room of three once one sensor has jumped. A
  disagreement between two cannot be put on either side; the room's
  last fused value, moved by its model to the moment, is a third that
  depends on neither reading now, its σ grown by what the model
  cannot tell over the time since. It comes from a Fused made with the
  tracks, so the jumped part is already out of it. The previous value
  holds both sensors' deltas, so a bias on one is in part put on the
  other; that still beats standing still until a relearn. It is the
  aged-reading rule of the fusion, the same inputs from the snapshot,
  and stands aside where that rule does: no model, no outside the
  model needs, a Mode holding, or a previous value past `max_age`.
- **Updated from a Fused made without tracks**, so that each delta is
  taken out once, by the Tracker, and a drifting part, which a tracked
  Fused notes, is still updated and can clear. Until a part is flagged
  it still counts in the others' fusion, and leaks a little into their
  deltas.

## Staleness

- **A first-order ARX of the reference, per location and regime**: one
  state driven by the gap to the outside, each Switch's on-state and a
  constant, the discrete form of a one-resistance, one-capacitance
  room. Its inputs are what the learner reads; it is fitted in closed
  form, and refused when a < 0 (a room running away from the outside
  is not a room) or seen too little.
- **Every Switch by its hard hold**: the room's own time constant
  filters it already, and a filtered Switch's τ was chosen for a
  sensor's offset, not for the room. A Switch never off, or never on,
  in a regime is left out: its column would be the constant's.
- **Without the bins under a Mode, and not applied under one**: the
  aircon drives the room far more than anything the model has.
- **Kept only when it beats holding the last value** by
  `dynamics_margin`, two hours ahead, on the last tenth of its steps
  held out: rooms whose model wins or loses by a few thousandths are
  noise, not a model.
- **q from an hour ahead, not from one step.** The carried series is
  steady between reports, so its steps are far from independent; q is
  the mean square of the error of predicting an hour ahead, as the
  fusion does.
- **Only the time update, applied per reading.** No fused state is
  kept between calls: the fusion stays a function of the snapshot. The
  change is the model stepped over the reading's age, in closed form
  (an approach to the equilibrium the inputs hold the room at), so it
  holds at any age, and the validation forecasts the same way.
- **Send-on-delta as a cap, not a model.** A value that has not moved
  by its delta is within ±delta of the truth; spread evenly there its
  variance is delta² / 3. `max_age` still cuts: without a heartbeat,
  silence cannot be told from a dead sensor.

## Stores and names

- **The store is an interface**, so the core never depends on SQL.
  `Store::Sequel` creates its tables when missing, with names the
  caller chooses; a caller with its own schema creates them alike and
  passes `migrate: false`.
- **No column is named `group` or `condition`**: both are reserved in
  MySQL and MariaDB. Hence location, and influence.
- **Names are Strings**: an SQL store gives them back as Strings, so a
  Symbol given for an influence, a quantity or a regime is converted on
  the way in, or a term would stop applying after a round-trip.

## Ruled out

- **An inflation of the fused σ for shared errors**, learned by a
  leave-one-out on triple collocation σ: on the same data it is 1 by
  construction. Shared errors need a series that does not share them.
- **A lag term** (a lagged copy of a series): it narrowed nothing.
- **Online learning of the model's terms**: a weekly batch is enough;
  only the offset's level is followed online.
- **An IMM filter for jumps**: it needs transition probabilities and a
  jump size nobody has measured, and gives a probability where the
  fusion needs a decision.
- **A full RC network** for staleness: several parameters per room
  identified jointly with its neighbours, and a state carried across
  locations, for a first-order model that already wins little.
- **Learning the shift over the full model**: it needs the neighbour at
  the run's bins, and falls back to the plain offset when it is
  missing.
