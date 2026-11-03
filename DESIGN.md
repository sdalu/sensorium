# Design

Why sensorium is shaped as README.md describes, section by section in
the README's order; what was tried and dropped is under Ruled out.

## Learning

- **Medians for the constant and the switch terms**, least squares
  only for the linear terms. A median shrugs off the minutes a door is
  open.
- **A term is kept when it narrows p10..p90 to 80 %**, both spreads
  measured over the bins the term covers. A spread between quantiles,
  not a variance, for the same reason as the medians; the same bins,
  or a neighbour covering fewer of them could win by leaving the rough
  ones out.
- **The keep rule judges the correction, not the gap.** A correction
  divides the gap, and its width, by |1 + gain + k| (`Offset#correct`),
  so the Fusion, the Tracker and the Collocation all live in the
  correction's space; the 80 % test and the held-out one judged the
  gap. A k = −0.4 neighbour narrowing the gap to 70 % was kept while
  it widened the correction to 117 %, and a k = +0.6 one narrowing the
  gap to 90 % was refused while it narrowed the correction to 56 %.
  Both tests now take what a model leaves over its scale. On
  MadHouse's year (19 forward windows), the RMS of the corrected value
  went from 0.686 to 0.595 °C, the calibration unchanged, and the
  terms kept were worse than the constant on 9 of 74 sensor-windows
  instead of 36 of 66. A neighbour is now also a proxy for a driver
  (k > 0), not only a place the sensor also follows.
- **And when the bins held out confirm it, if they can.** Terms are
  chosen on all but the last tenth of the bins, then refitted on
  everything, as Dynamics are validated. A term the last tenth can try,
  what it adds varying over it, is kept only if it leaves that tenth's
  correction no wider: a model wider than its own plain constant on
  unseen bins is
  worse than the fallback it carries, and a neighbour the bins do not
  confirm makes the sensor depend on another for nothing (one house's
  mid-season Airzone kept one that left its last tenth 4 % wider). A
  term the tenth cannot try (a Switch never on in it, or on
  throughout: a constant there) leaves it as it was, and absence of
  evidence should not undo what the rest of the season showed: it is
  kept within 5 %. Not "narrower by a margin": a day's narrowing moves
  by 13 % on a room recorded over a winter, and the margin would refuse
  what the season showed for the noise of a few days; the widths carry
  that noise instead (below). The last tenth, not a random one:
  neighbouring bins are correlated, so bins drawn at random would
  confirm whatever was fitted beside them.

  ```text
  a sensor's calm bins, in time order
  ├─────────────── nine tenths ────────────────┤├─── last tenth ────┤
   terms chosen, each by the 80 % test           held out: each term
                                                 confirmed, and the
                                                 narrowing measured
  ├──────────── all bins: the terms kept, fitted again ─────────────┤
  ```
- **A term's widths as the bins held out confirm them.** The narrowing
  a term claims is measured on the bins it was chosen on, which a
  sensor's persistent error makes far fewer independent ones than they
  look (on the recorded room, 270 held-out bins are some 9
  independent; the 80 % test over 20 days holds about 90). There, a
  heating term chosen by the data narrowed one sensor's spread by
  26 % and the ten days after by 10 %: its σ too narrow, var(z) 1.17,
  the sensor overweighted. So the narrowing of the plain constant's
  spread the refit on all the bins claims is set against the one
  confirmed on the bins held out, and when those confirm less, the
  model's widths are widened by the ratio: its var(z) came back to
  0.83, the left-out RMS of the others no worse than without the term.
  The refit's claim, not the one made on the bins chosen on: the
  widths widened are the refit's, and it claims less, the bins held
  out among its own; set against the other, two of one house's terms
  the bins held out confirmed ended wider than their constant. On the
  house's year, learned on the first part of each regime and measured
  on the later bins, widths were 12 % too narrow unwidened and 5 % too
  wide widened. Not a stricter keep test: a term the bins held out
  only partly confirm is still worth what they confirm, and widening
  says how much. The plain constant is left as fitted; no term, no
  ratio.
- **An Offset's block share, from its own residuals.** The Tracker
  needs how much a block's mean innovation varies against one's. The
  residuals of the model learned are what the innovations are made of,
  less the others' share: their block mean keeps 0.82 to 0.85 of
  their spread on the recorded room, the innovations' some 0.77; a
  little wide, so a little slow to flag, and learned with the offset
  rather than by replaying the Tracker over the span.
- **The gain and the neighbour fitted together** when both are kept.
  Both regress on the reference's level (r, and r − n), so fitted one
  after the other the second would be biased by the first. The one that
  narrows most alone goes first; the pair is kept only if it narrows
  that one again. The pair is fitted by least squares, not Deming:
  r carries the reference's error in both columns, and a two-column
  errors-in-variables fit needs the error covariance of r − n too,
  which nothing measures. A pair's gain is therefore biased toward
  zero by about σ²/var(r).
- **A greedy choice.** Terms are chosen one at a time, each tested on
  what the ones before it left (the 80 %): simple, and each step's test
  honest. A term fitted early can take in some of a later one's share
  where their regressors move together; with a single term beside the
  constant, which is all the house measured ever kept, there is no
  share to divide.
- **A gain alone is a Deming line.** Least squares of s − r on a noisy
  r biases the gain toward zero by about σ²/var(r), and within one
  regime var(r) is small. The gain is a Deming line of s on r, the
  variance ratio being what s's error is once r's (the quantity's σ)
  is taken out of the spread the line leaves, at least `floor`²,
  re-estimated until it settles. It is there for sensors wrong by a
  share (CO₂, light, particles); `Setup#gain` turns it off, and the
  room preset leaves it off with the rate term: no sensor of the house
  measured kept either.
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
- **One History for the four learners.** The Learner, Dynamics,
  Collocation and Transient read the same span, and a year of readings
  is most of a relearn's time: read once, and the carried reference
  series found once, the four learners cannot disagree on what the
  reference was. Collocation reads the History rather than subclassing
  the Learner: it needs the Learner's series, not its fit, and a
  subclass reaching into another class's private state breaks with
  every change to it.
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
  are its own yardstick, per regime and direction.
- **A quantile at a target rate, not a multiple of a spread.** The
  changes are stepped (most are 0 on a sensor that reports in tenths)
  and heavy-tailed: a median absolute deviation is 0 for a third of
  one house's sensors, and where it is not, a z of 5 on it still fires
  several times a day. What a user can choose is how many false
  alarms a day to bear; the quantile at 1 − rate / bins a day is the
  change exceeded that often, whatever the shape. A fall and a rise
  each have their own, the two tails being unlike (in one house's
  green-room, a ceiling sensor's winter rise threshold is nearly
  twice its fall). A quantile of 0 would make every step an event: it
  is raised just past the sensor's smallest step.
- **Two thresholds.** A window opened cools the whole room: live, a
  sensor's own change says so, whatever its reference does. For
  learning only a sensor moving apart from its reference distorts its
  offset; a whole-room change (the radiators starting) moves both and
  leaves the gap alone. Hence the own threshold for the Detector, the
  relative one for the influence, and none relative for a reference,
  which has no gap to itself.
- **Left out, not modelled**, as a Mode is: what an airing, a shower
  or a ray of sun does to a sensor depends on the moment (how wide the
  window, how cold outside, where the sun falls), not on any series
  the source tells; a term fitted to it would be noise. No Shift
  either: a transient has no value to learn one per.
- **Opt-in for learning**: at the earlier thresholds it widened
  downstairs/tado/mid and green-room/tado/mid by over 5 %, and read
  FakeHouse's heating step as a transient, so the room preset leaves it
  out.
- **The Tracker stands aside during an event.** An opened window
  reads, to the CUSUM, as a step; a long one could push it past h and
  leave a track jumped for a day and more, until the return test
  clears it. The whole location is left as
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
  is exactly the inverse-variance fusion, for three parts or more.
- **Two parts by inverse variance, σ widened by their disagreement.**
  Student-t reweighting of two parts that disagree slides to the one
  with the smaller σ: on the recorded room, a 3 % change of one σ
  moved the fused value by 1.8 °C. With two there is no majority to
  call one an outlier. Below three parts the inverse-variance mean is
  taken, its σ widened by max(1, |a − b| / √(σa² + σb²)): a pair that
  disagrees beyond its σs says one of them is wrong, and the σ says
  so. On MadHouse's year, two-part moves above σ fell from 22 to 0;
  the widening also stopped a reference being flagged at a heating
  start (z 5.65 to 2.88).
- **A transform, not a humidity model.** Relative humidity depends on
  the sensor's own temperature; in absolute humidity the sensors'
  errors add up again, so the same learner and fusion apply. The
  context (temperature) travels with each reading, and the fused value
  is brought back at the location's fused temperature, which the caller
  gives.
- **Settings per quantity**: a smoke detector may be the temperature
  reference and not measure humidity at all, hence the humidity
  preset's own places (wall, valve).
- **A sole reference's σ from its collocation.** A sole reference's σ
  was the quantity's, a hand-set 0.1 °C, yet it anchors every weight:
  on NoisyRoom, a reference three times noisier made the fused value
  overconfident (var(z) against the truth 6.94) and took the most
  weight (0.83). Where the Location sets none, a sole reference now
  takes the σ its Collocation measured, bounded below by the
  quantity's floor and above by the tightest σ of the corrections to
  it, every one of which holds the reference's error: var(z) 0.41,
  weight 0.32. Not with several references, nor where the
  Collocation finds the reference not measurable (a negative
  variance). With a noisy reference the fused
  σ then errs wide (0.41): the safe side. On MadHouse's year, rooms of
  three went from 24 to 30 jumps (false 15 to 19, real 2 to 3), var(z)
  and RMS unchanged.
- **Triple collocation feeds the reference's σ, and nothing more.** It
  tells each series' own error apart, assuming the errors independent:
  an error every series shares is in no difference, and one shared by
  every series but one is put on that one. Taken out of each sensor's
  σ as well, it moved the shared error from one σ to another rather
  than accounting for it (Ruled out); so it gives the reference its σ,
  which nothing else measures, and stays a measurement for the rest.

## Staleness

- **An old reading ages by the drift rule only.** A location's
  Dynamics model used to move an old reading to the moment. On
  MadHouse's year it moved values by 0.017 °C RMS and the left-out RMS
  by 0.006 °C on the hours it touched (0.002 over the year), and
  narrowed σ too far on readings 30 to 60 minutes old: var(z) 1.34 in
  rooms of two, one sparse reading swinging red-room by 1.6 °C.
  Without the outside series it acted in two months only. So an old
  reading's σ always grows by drift × its age, its value unmoved, and
  the Fusion takes no dynamics.
- **Dynamics stays, as a toolkit.** The model, its learning, its
  validation, its forecast and the stores that keep it are for a
  caller that predicts a room, such as a heating planner; the bullets
  below are why it is shaped so.
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
- **Without the bins under a Mode**: the aircon drives the room far
  more than anything the model has.
- **Priors as numbers, not physics.** A room's time constant and
  heating gain follow from its walls, volume and ventilation, but those
  are a building's, not a sensor's, and the method that turns them
  into numbers is a country's: sensorium takes the result, a Gaussian
  prior per coefficient, added to the least squares, and leaves where
  it comes from to the caller.
- **Kept only when it beats holding the last value** by
  `dynamics_margin`, two hours ahead, on the last tenth of its steps
  held out: rooms whose model wins or loses by a few thousandths are
  noise, not a model.
- **q from an hour ahead, not from one step.** The carried series is
  steady between reports, so its steps are far from independent; q is
  the mean square of the error of predicting an hour ahead, as a
  forecast does.
- **The change in closed form.** It is the model stepped over the
  hours asked, in closed form (an approach to the equilibrium the
  inputs hold the room at), so it holds at any horizon, and the
  validation forecasts the same way.
- **Send-on-delta as a cap, not a model.** A value that has not moved
  by its delta is within ±delta of the truth; spread evenly there its
  variance is delta² / 3. `max_age` still cuts: without a heartbeat,
  silence cannot be told from a dead sensor.

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
  own truth. A sensor whose single other is the reference is judged
  against it alone (below); any other part with fewer than two others
  is left as it was.
- **One model behind the rules.** The attribution is one model in the
  correction's space: a common mode, the reference's error, whose
  innovation is the robust consensus of the sensors' differentials
  against the reference; and one differential per sensor, judged
  against a GLS blend of the reference and the other sensors'
  consensus, with weight ρ = σr² / (σr² + spread²) on that consensus.
  The rules below are that model's arithmetic: the references first,
  the suspect, a sensor against its reference alone (ρ = 0, no other
  sensor) and no lone reading against a single other (one sensor).
  With the reference's width kept, the model reproduced the Tracker on
  all 43 632 ticks of MadHouse's year. Only that width (the tightest
  Offset σ, below) is a rule of its own.
- **Widths in the correction's space.** delta and the innovations live
  in the correction's space, where a reading is corrected to the
  reference; the drift limit and a reference's width took an Offset's
  gap σ, so a sensor with a kept k = +0.6 neighbour drifted at 4.8 σ
  instead of 3. Both now take the corrected σ, the gap's over
  |1 + gain + k|.
- **A sensor against its reference alone.** The sensor's Offset was
  learned on exactly that pair, with that pair's spread as its σ, and
  the reference's delta is pinned at 0 by convention, so their
  disagreement is the sensor's. Two sensors without their reference,
  or two references, cannot attribute their disagreement: they stay as
  they are, and the Fusion's widening carries it into σ. On MadHouse's
  year (before this rule, then with it), a sensor's frozen part-hours
  in rooms of three fell from 11 406 to 5 430; green-room's October
  lock from 706 h to 31 h (a jumped tado's false jump clearing in 28 h
  instead of 730 h); a left-out part's var(z) and RMS equal or better
  for every part; and the rooms of two (bathroom, shower-room, garage)
  are tracked for the first time. The cost: a reference's excursion of
  hours can be put on the sensor judged against it alone (once on the
  year, downstairs/tado, 81 h), and in a room of two which part moved
  cannot be told. Limiting it to rooms that normally have three was
  rejected: the same pair knows the same thing, and "normally three"
  is arbitrary (green-room and red-room are pairs all summer by
  learning).
- **A slow filter, a CUSUM for jumps.** The gain is kept small so that
  noise does not move delta. `track_q` is in the quantity's units (how
  fast the offset itself wanders, in °C), so the filter's time
  constant varies with each sensor's corrected σ: 18 h to 152 h across
  MadHouse's offsets, median 44 h; a constant bias takes about two
  days to be learned near σ 0.25. Kept on purpose: a noisier sensor
  should take longer to show a drift. A step would then be absorbed
  over days, the value off
  all the while, so a two-sided CUSUM flags it (k = 0.5, h = 5, the
  textbook pair for a shift of one σ of what it runs on). A slow ramp
  the filter keeps up with is said by the drift alarm instead (|delta|
  past 3 Offset σ, cleared under 2). A jump flagged wrongly costs
  precision, not accuracy: the part is out, the others still corrected
  to the reference, the σ wider (losing a room's best sensor in
  winter, about ×3.7 on one house). A jump missed costs a bias the σ
  does not show. So the CUSUM is quick to flag, and a jump is cleared
  only by the same evidence, mirrored (below); the Tracker does not
  take a battery swap as an event.
- **A jump clears the way it came.** A jump is the CUSUM finding the
  innovations shifted by the size it is tuned for; the same evidence
  mirrored clears it. While jumped, delta and variance are held, the
  part is still scored without counting, and the CUSUM runs as the
  return test (up += k − z, down += k + z, each held between 0 and h +
  k): both sides above h, at least eleven blocks (33 h) of the error
  back, and it is ok again. No new constant. The ceiling is what keeps
  "back" meaning back: without it the side facing away climbed for as
  long as the error stood away, so an error that came back and
  overshot cleared within a block or two, and one settling a σ off
  cleared for good (found by a test, not on the year). On MadHouse's
  year every false jump the Tracker had flagged cleared, in about 2
  days (median) instead of at the monthly relearn (64 h once the
  ceiling below was in, with the rooms of two tracked; the fastest
  clear 22 h, where it had been 14 without it); both real steps stayed
  flagged while their error stood, and the time to a first jump was
  unchanged at every start. The limit: the delta held is the one at
  the jump, which has taken in part of a step during the detection
  delay, so such a part may not clear.
- **References tracked, but pinned.** A reference's reading is the
  location's definition of truth. Untracked, a reference that jumps
  makes every sensor beside it look jumped; tracked like the others,
  the deltas wander together and none learns a bias. So a reference
  runs the CUSUM and the jump state only, its delta pinned at 0.
- **A reference judged with the room's width.** Its offset is 0 by
  construction and its delta pinned, but what the Tracker measures of
  it is its disagreement with the room, whose usual size is not the
  instrument's σ but the scatter the learning measured: the tightest
  Offset σ of the location bounds the reference's own excursions
  against the room. A reference's innovations are judged with the
  larger of its σ and that tightest Offset σ; its own σ (the
  location's, the quantity's by default) stays the floor. On
  MadHouse's year the hours a reference spent jumped fell from 4946
  to 982, and one real divergence is now blamed on the right sensor.
  The cost: a reference step smaller than about the
  room's tightest Offset σ is not flagged (on the recorded room, steps
  of 0.10 and 0.15 °C, caught before at 4 and 6 of 16 starts after
  days, now at none); and in a room whose third sensor is noisy, which
  of the two tight ones a step between them is blamed on is still
  decided by noise. The one model above would judge the reference by
  its own σ instead; that was measured and not adopted (Ruled out).
- **References first, a jumped part out of the others.** A jumped part
  left in the others' fusion would pull them after it; within an
  update the references go first, and a part that has jumped is left
  out of every later part's others.
- **No witness.** A part left with a single other, as in a room of
  three once one part has jumped, used to take a witness as a second
  other: the previous Fused moved by the location's dynamics to the
  moment. With the room preset it stayed unused: green-room's model
  loses to holding by a hair (on MadHouse's year, a held-out ratio of
  0.987 to 0.996 in winter against the 0.98 margin; a 0.001 per bin,
  q 0.18 to 0.26 °C²/h). With the outside set and Dynamics learned
  monthly it brought no var(z) gain (an RMS 0.0025 °C lower), and let
  a reference be judged against a sensor plus a copy of the room's
  last value; once a sensor is judged against its reference alone,
  nothing was left for it to unfreeze. It is gone, and with it the
  Tracker's dynamics and the previous Fused a Tick or an update took.
  Without the dynamics MadHouse's year is unchanged tick for tick.
- **A Fused carries both estimates, and a Tick holds no state.** The
  value needs each part with its track applied; the Tracker needs it
  without, so that each delta is taken out once, by the Tracker, and a
  drifting part, which a tracked Fused notes, is still updated and can
  clear. Each Weighted part carries the part before its track beside
  the part after, so one fusion per location serves both, where two
  Fusions per tick computed every correction twice. The Tick keeps
  nothing between calls, as the Fusion keeps nothing (Staleness): the
  tracks come in with the Knowledge and go out updated, so a Tick is
  a function of what it is given
  and a store stays the one place the tracks live. Until a part is
  the suspect (below) it still counts in the others' fusion, and leaks
  a little into their deltas.
- **Blocks of three hours, not readings.** A sensor's error persists
  for hours: on the recorded room its innovations correlate at 0.5 an
  hour apart and 0.91 ten minutes apart. A CUSUM built for independent
  innovations then false-alarms within hours (for an AR(1) of 0.91, the
  mean run before a false alarm falls from some 440 steps to 43, seven
  hours at ten minutes); it flagged a wall sensor 6 to 11 hours into
  ten held-back days, and every part at ten-minute updates, with no
  step there, and once one part was out the two others stood aside
  (until a sensor beside its reference was judged against it
  alone).
  So the innovations are taken by blocks of `cusum_block`, about the
  time they take to decorrelate: the CUSUM runs on each block's mean,
  standardised by the Offset's block share, and k and h keep their
  meaning, one σ of a block. The same ten days: no part flagged, at
  either cadence; steps of 1, 2 and 3 Offset σ put into the readings
  flagged after 20, 8 and 5 hours at ten minutes (37, 10, 4 hourly);
  37, 10 and 5 at either cadence once the block under way counted for
  its share and a jump could clear (below).
  Blocks by time also make the alarm the same at any cadence, where a
  sensor reporting every five minutes got twice the CUSUM steps, and
  twice the false alarms, of one reporting every ten.
- **The Kalman step by blocks too.** Counted reading by reading, the
  same correlated innovations teach delta as if each were news: at
  five-minute readings a 3σ step was half taken into delta within
  eight hours, before any CUSUM over blocks could see it, and never
  flagged. Each reading now only walks the variance; a closed block's
  mean, its noise the mean reading's times the block share squared,
  is one Kalman step, taken after the CUSUM has seen it. delta then
  learns as fast at any cadence, and `track_q` doubles, to (σ/2)² in
  half a day: the old value was tuned while readings counted as
  independent, and halving the evidence halved the speed (a ramp of
  0.004 °C/h, drifting before, jumped).
- **The block under way, and a lone reading, count.** A step in the
  middle of a block is diluted by the readings before it; the block
  under way counts as if it closed now, its mean taken to vary as one
  reading (a mean of positively correlated readings varies no more),
  and a reading alone beyond h + k is a jump: a step far beyond the
  noise is flagged at once, a reference's 1 °C at its first reading
  where its room's offsets are no wider than the quantity's σ. Two
  later rounds narrow both (below): the block under way counts toward
  a jump for its share of a block, and a lone reading only against
  two others or more.
- **Against a single other, no lone reading is a jump.** The
  lone-reading rule is the Fusion's robustness lent to the Tracker:
  against two others or more, the truth's σ carries their disagreement
  (widened for two, Student-t for more), so a reading that far is the
  part's own; one other's reading cannot tell its own spike from the
  part's. Against a single other only a block's evidence counts, the
  CUSUM with the block under way for its share. No new constant. On
  MadHouse's year it removed 7 lone-reading jumps against the
  reference alone (among them the reference's 1-h spike put on
  downstairs/tado for 12 days); detection of 1 to 3 σ steps is
  unchanged; against a single other, 5 σ steps are flagged up to 2.1 h
  later and 10 σ steps 1.3 to 2.8 h later, never a block. On the
  recorded room no part is flagged at ten-minute ticks.
- **The block under way for the share of a block it spans.** It is
  correlated about 0.9 with the block just closed, so counting it as a
  full block right after a close counted the same evidence twice: on
  MadHouse's year, 12 of 16 jumps came at `block_count` 1 or 2. It now
  counts toward a jump for the share of `cusum_block` it spans. The
  suspect still counts it whole: being the suspect is a decision
  undone as soon as the CUSUM falls, and may use preliminary evidence.
  The cost: detection 0.5 to 2.9 h slower (medians over 16 starts on
  the recorded room), never a block.
- **The suspect.** Until a step is flagged, the others take it in: a
  reference stepping 5 σ, flagged after seven hours, left a third of
  it in an Airzone's delta, and with the reference out nothing takes
  it back before a relearn. So the part whose CUSUM is the highest,
  once past half of h, is left out of every other part's truth: the
  others no longer learn from it, and the leak fell to nothing.
  Only the highest: a reference's step pushes every part's CUSUM, and
  leaving all of them out of one another left none with two others,
  nothing updated, nothing flagged. And the suspect still learns:
  holding its delta turned a real bias into a jump, the CUSUM climbing
  on what the delta was not allowed to take in. No suspect is chosen
  below three tracks not jumped: with two parts there is no majority,
  and a suspect left out of a pair leaves the other nothing to learn
  from, so a stale suspect level locked the room. Letting the suspect
  count where leaving it out leaves one other was rejected: that is
  the leak the suspect rule exists against.

## Stores and names

- **The store is an interface**, so the core never depends on SQL.
  `Store::Sequel` creates its tables when missing, with names the
  caller chooses; a caller with its own schema creates them alike and
  passes `migrate: false`.
- **A column added later is added by `migrate`, and nullable.** The
  blocks brought five (`Schema::ADDED`); a store opened with
  `migrate: true` adds those its tables lack, and a row kept before
  them reads as a block not begun. Earlier additions were left to the
  caller, which a house's tables, migrated by hand, could not keep up
  with unaided.
- **No column is named `group` or `condition`**: both are reserved in
  MySQL and MariaDB. Hence location, and influence.
- **Names are Strings**: an SQL store gives them back as Strings, so a
  Symbol given for an influence, a quantity or a regime is converted on
  the way in, or a term would stop applying after a round-trip.

## Documents

- **Figures explain, they do not decorate.** Each figure sits next to
  the paragraph it illustrates, and that paragraph still reads on its
  own. Not a separate section of figures, and not figures in place of
  prose.

## Ruled out

- **A Kalman filter over the fused values.** Replayed on MadHouse's
  September and October (10-minute ticks, each room's reference held
  out), it narrowed σ by 28 % and the error not at all (RMS 0.223 to
  0.220 °C), so its 2σ coverage fell from 0.94 to 0.88: successive
  fused values share their offsets' error, which a filter averages as
  if it were noise. Updating only on newer readings changed nothing.
- **An inflation of the fused σ learned on held-out days.** Learned on
  MadHouse's September, it left October further from honest than no
  inflation at all (pooled var(z) 1.37 raw, 1.44 inflated): the excess
  was one sensor's level moving (downstairs Airzone, mean z +0.77), the
  Tracker's to follow, not a scale on σ.
- **A joint refit of the chosen terms.** No offset of the house kept
  two terms beside the constant, so it never ran; it returns if data
  ever needs it.
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
- **Scaling each innovation by its long-run variance** (z / √f, f the
  autocorrelation's sum): no false alarm, but the smallest step
  flagged grows to k√f, about 2 innovation σ at ten minutes, and the
  faster the cadence the larger f: a step of 1.9 σ was never flagged.
- **Prewhitening the innovations** (an AR(1) taken out): a level
  shift becomes one pulse of its size and a tail of a tenth, which no
  CUSUM sees; the false alarm on the recorded room stayed.
- **Counting `min_part` and the held-out bins in independent ones.**
  At the recorded room's correlation it would take three weeks of bins
  per term, and the count depends on the model it gates. The widths a
  term keeps are widened instead (Learning).
- **A held-out test by day** (a term kept when it narrows on most
  days held out), **or by folds**: the recorded room holds out two
  days, where a median of days is their mean; on MadHouse's year, with
  the keep rule on the correction, neither gained beyond its spread.
- **A cap on a neighbour's k**, instead of the keep rule on the
  correction: of two principled caps tried on MadHouse's year, one
  changed nothing where it mattered and the other removed the gain.
- **Raising the 80 % threshold, splitting the mid regime, or keeping
  every confirmed term at the refit**, beside the keep rule on the
  correction: on MadHouse's year none gained beyond its spread.
- **Two parts without the widening**, the plain inverse-variance
  fusion: it left a pair that disagrees overconfident, and doubled
  green-room's suspect time. **One Student-t step at every size**
  instead of three parts or more: it changed fusions of three parts
  or more by up to 0.42 °C.
- **The witness's dynamics with the outside series set.** While a
  part with a single other stood still, it unfroze only part of
  the three-sensor rooms, never green-room, and started
  tracking the noisy two-sensor rooms: jumps 14 to 21 on MadHouse's
  year.
- **A fresh track's prior from the Offset's width**: it absorbed both
  real steps of MadHouse's year.
- **The Detector's skip for transients alone**: it lengthened blocks,
  and new jumps came at the block after a skip.
- **A heating Series delayed and filtered, and PV power for the daily
  cycle**: the learner's own rules refused them on almost every
  sensor, and none gained when forced in.
- **Learning on fresh bins only** (`carry: 0`), or weighting a bin by
  its reading's age: 94 % of the bins hold a reading of their own, and
  the correlation is the room's, not the carry's.
- **A complementary filter** (the level from a slow sensor, the
  changes from a fast one): 0.30 °C against the inverse-variance
  fusion's 0.21; the best weights by time scale, 0.210 against 0.213.
- **A time-of-day term**, or one on the sun's elevation: a radiator
  valve's sensor keeps a daily swing (a quarter of its variance), and
  sin/cos of the hour narrow it by a quarter on held-back days, but on
  the days it was fitted on less than the 80 % asks.
- **Segmenting the history at change points** before learning: on the
  recorded room the one level change found was the heating's weather,
  and learning on the last segment made the σ too narrow.
- **A `track_q` estimated from the innovations** (Mehra): they are
  never white, whatever q, the daily cycle in them; no optimum exists.
- **Taking the reference's collocation σ out of each sensor's σ**,
  measured twice (as specified, and with a reference σ at the bound
  counted not measurable): on MadHouse's year the Collocation puts the
  downstairs sensors' shared errors on the reference, and a real 3 σ
  July step on the tado went unflagged, the reference blamed.
- **Carrying a track across a relearn** (delta rebased by the
  constant's move): false jumps 30 to 34 on MadHouse's year. Its
  post-relearn jumps come from the first learning and the regime
  boundaries, not from a track restarted on a rounded constant; an
  exact form needs the Offset's terms stored with the track.
- **Judging the reference by its own σ** in the Tracker, as the one
  model would without the width rule: it caught small reference steps
  on the recorded room, but added two false reference jumps on
  MadHouse's year. The width is kept until a second house can tell.
