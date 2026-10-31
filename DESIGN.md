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

## It learns what ClimatControl learned

With `Presets.room`, sensorium learns what `Sensing` learned. The
tests ported from ClimatControl (learner, fusion, offset, season,
stats) pass unchanged in substance. On MadHouse's real history
(2025-10-31 to 2026-10-31), both found the same 26 offsets with the
same neighbours and heating terms, constants and coefficients within
0.01 (sensorium rounds to 3 decimals, ClimatControl to 2), and the
same 17 aircon shifts within 0.005. No gain term was kept: for
temperature it narrows nothing, as ClimatControl had found.

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
  reference and not measure humidity at all.
- **The store is an interface**, so the core never depends on SQL.
  `Store::Sequel` creates its tables when missing, with names the
  caller chooses; a caller with its own schema (MadHouse: ASCII keys,
  foreign keys) creates them alike and passes `migrate: false`.
- **No column is named `group` or `condition`**: both are reserved in
  MySQL and MariaDB. Hence location, and influence.

## Ruled out

- **A lag term**: a lagged boiler-pipe gap gained nothing in
  ClimatControl's trials.
- **Online learning**: a year of MadHouse's history (some 30
  sensors) learns in about four minutes over the network; a nightly or
  weekly batch is enough.
