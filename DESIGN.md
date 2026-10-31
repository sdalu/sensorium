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
  that one again.
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

## Ruled out

- **A lag term**: a lagged boiler-pipe gap gained nothing in
  ClimatControl's trials.
- **Online learning**: a year of MadHouse's history (some 30
  sensors) learns in about four minutes over the network; a nightly or
  weekly batch is enough.
- **Learning the shift over the full model**, the other way to make a
  shift and its use agree: it needs the neighbour at the run's bins,
  and falls back to the plain offset anyway when it is missing. Under
  the aircon the blown air dominates; the plain offset loses little.
