# sensorium

Sensors of one quantity that share a location rarely agree: each is
biased by where it sits and by what runs near it. Sensorium learns,
from their history, how each one reads against the location's
reference, corrects each reading back to that reference, and fuses
them into one value with its uncertainty (σ).

It knows nothing of houses: what is measured, how the history is cut
into regimes, and what influences the sensors is told by a `Setup`.
`Sensorium::Presets.room` is the setup for the rooms of a house
(temperature or relative humidity).

Ruby ≥ 3.4, standard library only. Sequel only for the SQL store.

```ruby
# Gemfile
gem "sensorium", github: "sdalu/sensorium"
```

## Learning

```ruby
require "sensorium"

setup   = Sensorium::Presets.room                # temperature
learned = Sensorium::Learner.new(source, setup,
                                 from: Time.now - 365 * 86_400,
                                 to: Time.now).learn
learned.offsets   # [Sensorium::Offset], one per sensor and regime
learned.shifts    # [Sensorium::Shift], one per sensor, regime and mode
```

For every sensor of a location, bin by bin (10 minutes), the learner
models the gap to the location's reference r:

    sensor - r = constant
               + Σ switch terms (each while its Switch is on,
                                 or × its exposure when filtered)
               + Σ series coefficients × their values
               + gain × r
               + coefficient × (r - neighbour)
               + rate × dr/dt

- **constant**: the median gap.
- **switches**: an influence that is on or off (the radiators' water
  hot, house-wide, for an hour after a valve opened). A Switch given a
  time constant (`tau:`) is *filtered*: its term is term × exposure,
  the exposure a first-order filter of its on-state (0..1), and the
  time constant is chosen from those given (`Influence::TAUS`: 10 min,
  30 min, 1 h, 2 h) as the one that narrows most. A **threshold** is
  a switch the learner derives from the location's own reference: on
  while it read above a level within the past hours (a humidity
  sensor's creep after a shower).
- **series**: a level that moves the sensor in proportion (the PV
  inverter's power, for the sun on a sensor).
- **gain**: the sensor reads a share too high or too low. Fitted as a
  Deming line, the reference read with an error of its quantity's σ.
- **neighbour**: the sensor also follows another place: another
  location's sensor, or an external series (the outside). The one that
  fits best is chosen from the data.
- **rate**: the sensor is slower than the reference and lags it on
  every change (dr/dt per hour, `Setup#rate`).

Each term is kept only if it narrows the spread of what is left
(p10..p90) to 80 % of what it was, both measured over the bins the term
covers. The constant alone is kept too (`plain`), the fallback when the
neighbour, a series' value or dr/dt has no fresh value.

The influences a `Setup` names:

| influence | told by | learned as |
|---|---|---|
| `Influence::Switch` | events, on when true or positive | a term while on (`hold` after), or × its exposure with `tau:` |
| `Influence::Series` | events with numeric values, mean per bin, carried `hold` | coefficient × value |
| `Influence::Threshold` | nothing: the location's reference, as it reads, above `above` within `hold` | a term while on |
| `Influence::Mode` | events with a value | left out, a `Shift` per value |

```ruby
solar   = Sensorium::Influence::Series.new(name: "solar", hold: 1800)
heating = Sensorium::Presets::HEATING.with(tau: Sensorium::Influence::TAUS)
setup   = Sensorium::Presets.room.with(
    influences: [heating, Sensorium::Presets::AIRCON, solar]
)
```

A **mode** (the aircon heating or cooling) is not a term: the bins
under it, and its hold after, are left out of the fit, and each value it
takes is learned apart as a `Shift` on top of the plain offset.

Each **regime** (by default the calendar seasons) is learned apart.

A location's **reference** is the devices its `Location` names (their
mean when several, each then learned against it too), else its first
sensor tagged with one of the setup's `places` (for temperature,
"ceiling", then "floor"). A location with none is not learned.

## Fusing

```ruby
snapshot = Sensorium::Snapshot.from(source, setup, at: Time.now)
fusion   = Sensorium::Fusion.new(setup, offsets: store.offsets("temperature"),
                                        shifts: store.shifts("temperature"),
                                        locations: store.locations("temperature"))
fused = fusion.location("green-room", snapshot)
fused.value       # °C, corrected to the reference
fused.sigma       # one σ
fused.parts       # each sensor: raw, corrected, weight, note
```

Each reading is corrected to the reference with its offset (while a
mode holds, with the plain offset and the mode's shift), given what
holds at the moment: the switches and thresholds on, a filtered
switch's exposure over the 5 τ before, each series' latest value
within its hold, and dr/dt from the reference's two latest readings
within `max_age` (`Snapshot#history`). Without a series' value or
dr/dt, the plain offset. Each reading is weighted
by 1/σ². σ is never below the quantity's `floor`, grows with the
reading's age (see Staleness), and a reading older than `max_age`
does not count. A location without references set takes those it was
learned against in the moment's regime. With two sensors or more, the
inverse-variance fusion is Student-t reweighted (ν `robust_nu`) until
it settles: a part far from the rest counts for less, smoothly, rather
than one furthest part being dropped outright. A part whose final
weight falls below the quantity's `outlier_factor` share of 1/σ² is
noted `outlier`, but still counts for that little. Notes say why a
sensor does not count: `excluded`, `stale`, `not learned`,
`no context`, `outlier`. A location with no reference gets the plain
mean, `corrected` false and `sigma` nil.

### Staleness

A reading is an estimate of the reference when it was taken; by the
time it is fused, the room has moved on. By default its σ grows with
its age t (hours) as √(σ² + (drift × t)²), its value unmoved.

A location's **dynamics** do better where they were learned: a
first-order model of its reference r over one bin, per regime,

    r(t + bin) - r(t) = a × (outside - r) + Σ b[switch] × on + c + noise

with `outside` the external series `Setup#outside` names (none: a is
0) and `on` 1 while each Switch is on (its hard hold, not its
exposure). An aged reading is moved by what the model predicts over
its age, from the inputs at the moment (the outside's latest value
among the snapshot's externals, if no older than the location's
`max_age`, the Switches on), (a × (outside −
value) + Σ b × on + c) × age in bins, and its σ² grows by q × t, q
the variance the model leaves, per hour. Without a model for the
moment's regime, without the outside value when a ≠ 0, or while a
Mode holds (the model was fitted without those bins), the drift
rule.

```ruby
setup = Sensorium::Presets.room.with(outside: "outside")
models = Sensorium::Dynamics.learn(source, setup, from:, to:)
store.keep_dynamics("temperature", models)
fusion = Sensorium::Fusion.new(setup, offsets: store.offsets("temperature"),
                                      shifts: store.shifts("temperature"),
                                      locations: store.locations("temperature"),
                                      dynamics: store.dynamics("temperature"))
```

`Dynamics.learn` takes the location's reference as the learner does
(the `Location`'s, else the setup's `places`), fits the model by least
squares over the bins of the carried reference series where every term
is known and no Mode held (nor within its hold), and gives no model for
a location and regime seen less than `min_samples` steps, or with
a < 0 (a room running away from the outside is not a model). A Switch
never off, or never on, in a regime is left out: its term cannot be
told from c. q is the mean square of the error of predicting the
reference an hour ahead, as the Fusion does, over the bins fitted.

Each model is validated: fitted without the last tenth of its steps
(a week at least), it must predict the reference two hours ahead from
those steps with an RMS error at most `Setup#dynamics_margin` (98 %)
of holding the last value's, or the
location and regime get no model; kept, it is fitted again on all its
steps and carries both errors (`rms_hold`, `rms_model`). It is learned
apart from `Learner#learn`, so a caller can run it on its own schedule.

A **send-on-delta** sensor reports only when its value moved by a
threshold: an unchanged value is within that delta of the truth as
long as the sensor is alive. A `Location`'s `deltas` (`{ device =>
delta }`, as the quantity reads, before the transform) cap what the
age adds to σ² at delta² / 3, whichever rule gave it; the delta is
taken into the transform's space at the reading (2 %RH is some
0.35 g/m³ at 20 °C). `max_age` still cuts: a sensor silent for longer
may be dead.

```ruby
store.set_location("temperature", "green-room", { deltas: { "hue-1" => 0.2 } })
```

## Any quantity

```ruby
Sensorium::Quantity.new(name: "co2", unit: "ppm", sigma: 30, drift: 200)
```

A `Transform` takes a quantity where a sensor's error adds up, and back.
Relative humidity is learned and fused as absolute humidity
(`Transform::AbsoluteHumidity`): a sensor 1 °C warmer than the room
reads about 6 % lower for the same air. Each humidity reading needs its
sensor's temperature (`Reading#context[:temperature]`), and the fused
value is brought back at the location's temperature:

```ruby
humidity = Sensorium::Presets.room(Sensorium::Presets::HUMIDITY)
fusion.location("green-room", snapshot, context: { temperature: 20.4 })
```

A capacitive humidity sensor creeps: it reads high for hours after a
humid spell. The room preset adds, for humidity only, a threshold
"creep": on for six hours after the location's reference read above
80 %.

Ceiling and floor sensors (smoke and leak detectors) seldom measure
humidity: the room preset takes a sensor tagged "wall" (an aircon's
unit), else "valve" (a radiator's), as its reference. A shower moves
the humidity by several g/m³ in minutes; give such a room a wider
`drift` in its `Location`.

## The source

The learner and `Snapshot.from` read the history from any object that
answers, for a quantity's name:

| method | returns |
|---|---|
| `sensors(quantity)` | `[Sensor]`: name, location, tags, whether it may be a neighbour |
| `readings(quantity, from, to, devices)` | `[Reading]`: time, location, device, value, context; devices nil for all |
| `externals(quantity, from, to)` | `[Reading]` with location nil (optional) |
| `events(influence, from, to)` | `[[time, location, value]]` (optional) |

A reading's time is when its value was last known to hold. A sensor
that reports only changes (HomeKit) holds a steady value for hours: its
source re-emits the value, or stamps it with the last time the sensor
was heard from, or every steady reading turns stale. A `Location`'s
`deltas` (see Staleness) bound such a reading's σ, not its age: it
still needs the re-emission or the stamp to stay under `max_age`.

## Stores

A store keeps what a learning found and the locations' settings, by
quantity. `Store::Memory` for tests and one-off runs;
`Store::Sequel` (`require "sensorium/store/sequel"`) for any SQL
database, its table names configurable, its tables created when missing
unless `migrate: false`. An offset's maps (switches, taus, series)
are kept as JSON, as are a location's `deltas` and a dynamics model's
`b`. Tables made before the survey rounds lack three columns of
`sensor_offsets`: `taus` and `series` (text) and `rate` (float), and
`sensor_locations` lacks `deltas` (text); a caller with its own schema
adds them, and makes the fourth table, `sensor_dynamics` (`tables:
{ dynamics: }`), as `Store::Sequel::Schema.dynamics` does. Another
store answers the same eight methods (see
`lib/sensorium/store/memory.rb`).

Keeping dynamics (`keep_dynamics`) replaces the models of the same
location and regime, and leaves the others.

Keeping a learning replaces the offsets (and shifts) of the sensors it
learned again, and every offset of a location whose reference it found
changed. It leaves everything else: a sensor short of samples this
time keeps its offset, and a regime the span barely touched keeps its
model. A store's `learned` gives each regime the span of the latest
learning kept in it.

## Known shortfalls

- The fit is greedy, one term after the other; only the gain and the
  neighbour are ever fitted together.
- No term is learned online: a model changes only when learning runs
  again.
- The room preset's humidity σ and drift are first guesses, not
  measured.
- An offset of a sensor gone for good stays in the store until its
  location is learned against another reference.
- A dynamics model is a straight line over the reading's age (fine
  while a × age in bins is small: under 0.1 an hour on MadHouse), and
  its q is off by up to 4 × either way on MadHouse's October
  (DESIGN.md).
- A neighbour name is "LOCATION/DEVICE": a location "a/b" with a
  device "c" and a location "a" with a device "b/c" collide.

## Gate

`bundle exec rake`: the tests, then RuboCop.
