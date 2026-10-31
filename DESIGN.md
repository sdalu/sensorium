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

## Ruled out

- **A lag term**: a lagged boiler-pipe gap gained nothing in
  ClimatControl's trials. (The rate term above is not a lagged copy.)
- **Online learning**: a year of MadHouse's history (some 30
  sensors) learns in about four minutes over the network; a nightly or
  weekly batch is enough.
- **Learning the shift over the full model**, the other way to make a
  shift and its use agree: it needs the neighbour at the run's bins,
  and falls back to the plain offset anyway when it is missing. Under
  the aircon the blown air dominates; the plain offset loses little.
