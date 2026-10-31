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
  a room) or seen less than `min_samples` steps. The Switches enter
  by their hard hold, not their filtered exposure: the time constant
  of the room already filters them.
- **Only the time update, applied per reading.** No fused state is
  kept between calls: the Fusion stays a function of the snapshot.
  Each reading is moved by the model's predicted change over its age,
  from the inputs at the moment, and its σ² grows by q × age. The
  change is a straight line (Euler over the age): with a below 0.014
  per bin on MadHouse and `max_age` an hour, a × age stays under 0.1.
- **Send-on-delta as a cap, not a model.** A value that has not moved
  by its delta is within ±delta of the truth; spread evenly there its
  variance is delta² / 3. The cap applies to whichever age term holds,
  and `max_age` still cuts: without a heartbeat, silence cannot be told
  from a dead sensor.

What MadHouse's year showed (`Presets.room`, outside: the weather
station; learned 2025-10-31 to 2026-10-31, 26 models of 9 locations,
12 400 to 16 900 steps each; toilet-downstairs got no summer model,
refused for too few steps or a < 0, the run did not print which).
Outside summer the living rooms follow the outside with τ = bin / a of
67 to 260 h, the toilets hardly at all (500 to 3 300 h), the garage in
13 to 17 h; in summer τ is longer still in most rooms (up to 1 600 h).
The heating term is 0.01 to 0.03 °C per bin in winter in seven
locations of nine; c carries the rest. q is 0.004 to 0.11 K² per hour,
against the drift rule's 1 K² after an hour.

Held out, the model trained to 2026-10-01 predicted October's
reference (the "mid" models, about 4 300 starts per location), RMS in
°C, holding the last value against the model as the Fusion applies it
(inputs at the target time):

| location | 1 h hold | 1 h model | 2 h hold | 2 h model | 4 h hold | 4 h model |
|---|---|---|---|---|---|---|
| bathroom | 0.359 | 0.359 | 0.407 | 0.407 | 0.456 | 0.463 |
| downstairs | 0.286 | 0.283 | 0.433 | 0.428 | 0.613 | 0.600 |
| garage | 0.365 | 0.276 | 0.648 | 0.425 | 1.131 | 0.698 |
| green-room | 0.214 | 0.217 | 0.317 | 0.325 | 0.480 | 0.499 |
| red-room | 0.450 | 0.452 | 0.534 | 0.542 | 0.613 | 0.668 |
| shower-room | 0.068 | 0.063 | 0.118 | 0.110 | 0.210 | 0.203 |
| toilet-downstairs | 0.045 | 0.044 | 0.066 | 0.064 | 0.108 | 0.103 |
| toilet-upstairs | 0.058 | 0.058 | 0.090 | 0.090 | 0.147 | 0.152 |
| under-the-sink | 0.269 | 0.266 | 0.447 | 0.435 | 0.670 | 0.658 |
| all, pooled | 0.274 | 0.262 | 0.392 | 0.357 | 0.577 | 0.502 |

Stepping the model bin by bin with each bin's inputs did about as
well (pooled 0.263, 0.362, 0.496). The garage gains most; most rooms
gain a little; green-room and red-room do slightly worse than holding
at every horizon. Within `max_age` (an hour) the change the model
predicts is small but for the garage: its gain at fusion is mostly in
σ, which no longer swamps an hour-old reading. That σ is not
calibrated: the hold-out's 1 h error variance is about 3 × q in
bathroom, downstairs, red-room and under-the-sink (2 × in
green-room), and 0.5 to 0.9 × q in the garage, the shower room and the
toilets. A per-step residual variance scaled to an hour assumes
independent steps; the carried series, steady between reports, makes
them anything but.

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
  carry a state across locations. The held-out month leaves little for
  it: over an hour, the first-order model already moves the value
  little, and holding the last value is within 0.06 °C of it at every
  horizon everywhere but the garage.
- **Learning the shift over the full model**, the other way to make a
  shift and its use agree: it needs the neighbour at the run's bins,
  and falls back to the plain offset anyway when it is missing. Under
  the aircon the blown air dominates; the plain offset loses little.
