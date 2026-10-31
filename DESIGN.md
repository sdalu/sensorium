# Design

## Where it comes from

Sensorium was ClimatControl's `Sensing` module (ClimatControl at
666263f, `lib/climat_control/sensing/`), which learned the
temperature sensors of one house against each room's ceiling sensor.
It was taken out on 2026-10-31 so that MadHouse could fuse the same
readings into its own table, and made generic on the way. Everything
house-specific became configuration:

| in ClimatControl | in sensorium |
|---|---|
| `Reading#temperature` | `Reading#value`, a `Quantity` |
| zone | location |
| ceiling, else floor sensor | `Setup#places`, tags on a `Sensor` |
| `HEATERS = tado, airzone` | `Sensor#neighbour` false |
| zone `"outside"` | `externals`, location nil |
| `hot` (valves, house-wide) | an `Influence::Switch`, any number of them |
| `aircon` mode | an `Influence::Mode`, any number of them |
| seasons by month | a `Regime` |
| constants | `Setup` and `Quantity` settings |
| `sensor_rooms` | `sensor_locations`, by quantity |

## What it learns against ClimatControl

With `Presets.room`, sensorium learns what `Sensing` learned, but for
the departures below, which are corrections. On MadHouse's real
history (2025-10-31 to 2026-10-31), both found the same 26 offsets and
17 aircon shifts; 25 offsets have the same neighbours and heating
terms, constants and coefficients within 0.01 (sensorium rounds to 3
decimals, ClimatControl to 2), the shifts within 0.005. The 26th,
downstairs Airzone in winter, follows the garage's other sensor
(branch, not keith-richards): judged over the same bins, it narrows
more. No gain term was kept: for temperature it narrows nothing, as
ClimatControl had found.

Where sensorium departs from `Sensing`, on purpose:

- **A term is judged over the bins it covers.** `Sensing` compared a
  neighbour's spread over the bins it covers with the kept model's over
  all of them, so a neighbour could win by leaving the rough bins out.
- **A shift applies over the plain offset**, the one it was learned
  over. `Sensing` added it to the full model: wherever a neighbour was
  kept, a reading under the aircon was off by the neighbour's term
  (2.7 °C in a constructed case).
- **The reference is the moment's regime's.** `Sensing` took the first
  regime's, so a location learned against another sensor in summer
  lost its summer model.
- **A learning replaces what it learned again**, not whole regimes: a
  span that barely touches a regime, or a sensor short of samples,
  used to wipe a model that was still good.
- **σ has a floor**: a spread learned at zero (a sensor reading in
  steps) made one sensor take all the weight, and fusion fail at age 0.

## Choices

- **Medians for the constant and the switch terms**, least squares
  only for the linear terms. A median shrugs off the minutes a door is
  open; it is what `Sensing` did, and it kept the regression exact.
- **A term is kept when it narrows p10..p90 to 80 %.** A spread
  between quantiles, not a variance, for the same reason.
- **The gain and the neighbour fitted together** when both are kept.
  Both regress on the reference's level (r, and r − n), so fitted one
  after the other the second would be biased by the first. The one that
  narrows most alone goes first; the pair is kept only if it narrows
  that one again. The pair is fitted by least squares, not Deming:
  r carries the reference's error in both columns, and a two-column
  errors-in-variables fit needs the error covariance of r − n too,
  which nothing measures yet. A pair's gain is therefore still biased
  toward zero by about σ²/var(r).
- **The gain is new.** It did nothing for temperature; it is there for
  sensors wrong by a share (CO₂, light, particles). `Setup#gain` turns
  it off.
- **Modes are left out, not modelled**: what blown air does to a sensor
  depends on where it sits and how the air flows, not on any series we
  have. A shift per value, over the plain offset, is all the data
  supports.
- **A transform, not a humidity model.** Relative humidity depends on
  the sensor's own temperature; in absolute humidity the sensors'
  errors add up again, so the same learner and fusion apply. The
  context (temperature) travels with each reading, and the fused value
  is brought back at the location's fused temperature, which the caller
  gives.
- **Settings per quantity**: a smoke detector may be the temperature
  reference and not measure humidity at all; in the house measured,
  none of the ceiling or floor sensors did, hence the humidity
  preset's own places (wall, valve).
- **Names are Strings**: an SQL store gives them back as Strings, so a
  Symbol given for an influence, a quantity or a regime is converted on
  the way in, or a term would silently stop applying after a
  round-trip.
- **The store is an interface**, so the core never depends on SQL.
  `Store::Sequel` creates its tables when missing, with names the
  caller chooses; a caller with its own schema (MadHouse: ASCII keys,
  foreign keys) creates them alike and passes `migrate: false`.
- **No column is named `group` or `condition`**: both are reserved in
  MySQL and MariaDB. Hence location, and influence.
- **Student-t reweighting, not a single 3σ drop.** The old rule found
  the one part furthest from the inverse-variance fusion of the others
  and dropped it outright past 3σ; it only looked at one part at a
  time, so two sensors wrong together (the same radiator plume, the
  same stuck valve) could each pass the test while the pair still
  pulled the fused value off. Reweighting every part by a Student-t
  factor on its own residual, iterated to convergence, downweights
  however many parts disagree, smoothly instead of as a hard cut, and
  a part that only mildly disagrees (seen mostly with two parts
  counted) is only mildly downweighted. It costs the `quantity.outlier`
  σ threshold, replaced by `robust_nu` (how hard a disagreement is
  punished) and `outlier_factor` (how little weight is left before the
  note says so); when every part agrees, the result is exactly the old
  inverse-variance fusion.

## Terms from the literature survey (2026-10-31)

A survey of in-situ calibration (sections 3.3, 5.2 and 5.3) proposed
five terms. Each is tried under the same keep rule, so a house where
none narrows learns what it learned before. On MadHouse's year
(2025-10-31 to 2026-10-31, `Presets.room` plus a solar Series) the
temperature learning found the same 26 offsets and 17 shifts as
before, and no new term was kept; the ratios below are the best each
term reached (kept at 0.8).

- **Solar (`Influence::Series`).** The survey's largest error source
  for unshielded sensors is the sun, and a PV inverter is a fair
  irradiance meter. Learned as coefficient × the inverter's AC power,
  mean per bin, carried `hold`. At fusion the latest value within
  hold, else the plain offset. On MadHouse it came closest on the
  garage's branch sensor (0.80 in mid-season, −0.45 °C/kW; 0.89 in
  winter), then red-room's Airzone (0.92); elsewhere 0.97 or more. It
  was never tried in summer: the inverter's log has a gap (August
  43 %, September 4 % of bins), so it covers some 60 % of the summer
  bins, short of `covers`.
- **Filtered switches (`tau:`).** A step window says the radiators
  act fully from the valve's first minute and stop dead after the
  hold; heat arrives and leaves gradually. With `tau:` the term is
  term × a first-order filter of the on-state, the time constant the
  one of `Influence::TAUS` that narrows most, stored per offset;
  without, the hard hold, unchanged. `tau:` takes seconds or a list:
  the brief said both "seconds" and "choose from {600…7200}". Learned
  with `Presets::HEATING.with(tau: TAUS)`, green-room's tado in
  mid-season kept it (τ 2 h, 0.445 °C, p90−p10 0.535 → 0.495, where
  the hard term had 0.34); no other offset kept heating either way
  (best 0.83, green-room's tado in winter, τ 2 h). Long after the last
  valve opened the exposure is exactly 0: its tail of 1e-300 values
  had given a summer slope of 1e140, refused, but a hazard.
- **Reference rate (`Setup#rate`).** Sensors with different time
  constants disagree on every transient by about τ·dr/dt. Unlike the
  lagged copy ruled out below, the term is the reference's own rate
  (per hour, central difference over a bin each side), tried after the
  gain and the neighbour. At fusion dr/dt comes from the reference's
  two latest readings within `max_age`, else the plain offset. On
  MadHouse the best was the garage's branch sensor in summer (0.90,
  a lag of 43 min), red-room's Airzone in summer 0.92 and the shower
  room's tado (0.95, reading 1.5 h ahead rather than behind); nothing
  near 0.8.
- **Deming gain.** Least squares of s − r on a noisy r biases the gain
  toward zero by about σ²/var(r), and within one season var(r) is a
  few K². The gain is now a Deming line of s on r, the variance ratio
  being what s's error is once r's (the quantity's σ) is taken out of
  the spread the line leaves, at least `floor`², re-estimated until
  it settles. On MadHouse it changed nothing: no gain was kept, the
  closest the garage's branch sensor in mid-season (0.89).
- **Humidity creep (`Influence::Threshold`).** Capacitive RH sensors
  read high for hours after a humid spell. A Threshold is on while the
  location's reference, as it reads (RH, before the transform), was
  above `above` within `hold`, and learned as a Switch. The humidity
  preset adds "creep" (80 %, 6 h). Not measured on MadHouse: the
  prototype source tags no sensor "wall" or "valve", so the humidity
  learning found no reference and learned nothing.

## Staleness (2026-10-31)

The survey (sections 4, 5.2 item 7, 5.3 item 5) found the linear σ
growth the weakest part of the fusion: an hour-old reading lost
almost all its weight (drift 1 °C/h against σ 0.1), whatever the room
was doing, and a report-on-change sensor's steady value looked stale
though it was known to be within its reporting step.

- **A first-order ARX of the reference, per location and regime.**
  One state, r, driven by the gap to the outside, each Switch's
  on-state and a constant: the discrete form of a one-resistance,
  one-capacitance room (a = bin / τ), which is what the survey's
  Kalman time update needs and nothing more. Its inputs are already
  what the learner reads; it is fitted in closed form by least
  squares on the carried reference series, as the learner builds it,
  and refused when a < 0 (a room running away from the outside is not
  a room) or seen less than `min_samples` steps.
- **Every Switch by its hard hold**, a filtered one too: the room's
  own time constant filters it already, and the exposure's τ was
  chosen for a sensor's offset, not for the room.
- **A Switch never off, or never on, in a regime is left out** of that
  regime's fit: its column would be the constant's, or nothing.
- **The bins under a Mode are left out of the fit**, and its hold
  after, as the learner does for the offsets: the aircon drives the
  room by far more than anything the model has, and a synthetic
  aircon cooling the room two hours a day biased a by a quarter.
- **Kept only when it beats holding the last value.** Each location
  and regime is fitted without the last tenth of its steps (a week of
  them at least), then predicts the reference two hours ahead from
  each of those steps, as the Fusion would; it is kept only if its RMS
  error is at most 98 % of holding's (`Setup#dynamics_margin`), then
  fitted again on all its steps. Both errors stay on the model
  (`rms_hold`, `rms_model`). The margin is there because most rooms
  won or lost by a few thousandths, which is noise: green-room's mid
  model won its May validation by 0.7 % and lost in October.
- **Not while a Mode holds.** The model is fitted without the bins
  under a Mode, so it says nothing of them: while the aircon runs, a
  reading ages by the drift rule.
- **q from an hour ahead, not from one step.** The carried series is
  steady between reports, so its steps are far from independent, and
  six times a step's residual variance said little of an hour's error.
  q is the mean square of the error of predicting an hour ahead, as
  the Fusion does, over the bins fitted. On a synthetic room whose
  noise is an AR(1) of coefficient 0.9 it comes within 4 % of the true
  hour's error; the one-step rule gave a fourteenth of it.
- **Only the time update, applied per reading.** No fused state is
  kept between calls: the Fusion stays a function of the snapshot.
  Each reading is moved by the model's predicted change over its age,
  from the inputs at the moment (the outside only if read within the
  location's `max_age`), and its σ² grows by q × age. The change is a
  straight line (Euler over the age): with a below 0.014 per bin on
  MadHouse and `max_age` an hour, a × age stays under 0.1.
- **Send-on-delta as a cap, not a model.** A value that has not moved
  by its delta is within ±delta of the truth; spread evenly there its
  variance is delta² / 3. The cap applies to whichever age term holds,
  and `max_age` still cuts: without a heartbeat, silence cannot be told
  from a dead sensor.

What MadHouse's year showed (`Presets.room`, outside: the weather
station; 2025-10-31 to 2026-10-31, 27 regimes over 9 locations). The
run kept a model whenever it beat holding at all: 20 kept, 7
refused. With the 2 % margin, applied after it from the same numbers,
11 are kept: downstairs in winter and summer, the garage in all three
seasons, red-room mid-season, the shower room in winter and summer,
toilet-downstairs mid-season, toilet-upstairs in winter, under-the-sink
in summer. The run's table:

| location | winter | mid | summer |
|---|---|---|---|
| bathroom | kept (0.322 → 0.318) | refused (0.440, 0.442) | kept (0.353 → 0.353) |
| downstairs | kept (0.310 → 0.291) | kept (0.525 → 0.524) | kept (0.274 → 0.256) |
| garage | kept (1.018 → 0.730) | kept (0.698 → 0.528) | kept (0.883 → 0.563) |
| green-room | kept (0.529 → 0.523) | kept (0.540 → 0.536) | refused (0.217, 0.233) |
| red-room | refused (0.280, 0.281) | kept (0.619 → 0.563) | kept (0.354 → 0.350) |
| shower-room | kept (0.162 → 0.151) | refused (0.123, 0.128) | kept (0.092 → 0.090) |
| toilet-downstairs | refused (0.059, 0.059) | kept (0.065 → 0.063) | refused: a < 0 or singular on the first nine tenths |
| toilet-upstairs | kept (0.150 → 0.136) | refused (0.090, 0.094) | kept (0.069 → 0.069) |
| under-the-sink | kept (0.544 → 0.536) | kept (0.559 → 0.549) | kept (0.390 → 0.375) |

(the validation's RMS two hours ahead, °C: holding → the model.) Only
the garage gains clearly; elsewhere a model is kept or refused by a
few thousandths. The aircon holds in most of green-room's and
red-room's mid and summer bins: 2 500 to 4 600 steps are left, against
some 12 500 elsewhere. τ = bin / a is 12 to 17 h in the garage, 36 to
200 h in the living rooms, 600 to 3 300 h in the toilets; the heating
term is 0.01 to 0.03 °C per bin in winter in seven locations of nine.
q is 0.0025 to 0.26 K² per hour.

Held out: the models learned 2025-10-31 to 2026-10-01 (validated
the same way, so for "mid" on its last tenth, in May) predicted October's
reference. Only three locations kept a "mid" model; RMS in °C from the
starts outside a Mode, holding against the model as the Fusion applies
it, then q against October's mean square error an hour ahead:

| location | starts | 1 h hold | 1 h model | 2 h hold | 2 h model | 4 h hold | 4 h model | q | 1 h MSE |
|---|---|---|---|---|---|---|---|---|---|
| garage | 4 326 | 0.365 | 0.276 | 0.648 | 0.425 | 1.130 | 0.697 | 0.339 | 0.076 |
| green-room | 232 | 0.198 | 0.198 | 0.345 | 0.346 | 0.554 | 0.557 | 0.063 | 0.039 |
| red-room | 275 | 0.357 | 0.343 | 0.530 | 0.474 | 0.649 | 0.615 | 0.050 | 0.118 |
| pooled | | 0.358 | 0.277 | 0.630 | 0.425 | 1.087 | 0.687 | | |

Over every start, the aircon's included (green-room and red-room
4 326 and 4 324), green-room's model is worse than holding at every
horizon (1 h 0.216 against 0.214, 2 h 0.323 against 0.317, 4 h 0.501
against 0.480), red-room's too (0.452 against 0.450, 0.548 against
0.534, 0.703 against 0.612), and red-room's hour error is 4 × q: the
Fusion applies a model under the aircon that was not fitted there.
The validation in May did not foresee October's green-room;
its margins are of the order of their noise. q is now on the safe
side in the garage (4 × October's error: April and May moved it more)
and in green-room (1.6 ×), still short in red-room (2.4 × short).

## Ruled out

- **A lag term**: a lagged boiler-pipe gap gained nothing in
  ClimatControl's trials. (The rate term above is not a lagged copy.)
- **Online learning**: a year of MadHouse's history (some 30
  sensors) learns in about four minutes over the network; a nightly or
  weekly batch is enough.
- **A full RC network** for staleness (several capacitances per room,
  walls, rooms coupled to each other), the grey-box hierarchy the
  survey cites: each location would need several parameters
  identified jointly with its neighbours (maximum likelihood on
  stochastic differential equations), and the fusion would have to
  carry a state across locations. The validation leaves little for it:
  two hours ahead, the first-order model beats holding the last value
  by a few hundredths of a degree at most, everywhere but the
  garage.
- **Learning the shift over the full model**, the other way to make a
  shift and its use agree: it needs the neighbour at the run's bins,
  and falls back to the plain offset anyway when it is missing. Under
  the aircon the blown air dominates; the plain offset loses little.
