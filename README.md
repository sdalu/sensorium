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
reading's age (`drift` per hour), and a reading older than `max_age`
does not count. A location without references set takes those it was
learned against in the moment's regime. With two sensors or more, the
inverse-variance fusion is Student-t reweighted (ν `robust_nu`) until
it settles: a part far from the rest counts for less, smoothly, rather
than one furthest part being dropped outright. A part whose final
weight falls below the quantity's `outlier_factor` share of 1/σ² is
noted `outlier`, but still counts for that little. Notes say why a
sensor does not count: `excluded`, `stale`, `not learned`,
`no context`, `jumped` (its track says so, see Tracking), or that it
counts with a caveat: `outlier`, `drifting` (its track says so). A
location with no reference gets the plain mean, `corrected` false and
`sigma` nil.

## Tracking

Between two learnings an offset can move: a sensor moved, re-batteried
or ageing reads wrong until the next learning. The `Tracker` follows,
for each sensor with an `Offset`, a `Track`: `delta`, its corrected
value minus the truth, as estimated, with its `variance`; the two sides
of a CUSUM; `at`, the time of its last update; and a `state`, `:ok`,
`:drifting` or `:jumped`.

The truth, for one part of a `Fused`, is the `Combine.robust` fusion
of the other parts that count (a value and a σ, no note but
`outlier`), each with its own delta taken out. A part with fewer than
two others is left as it was. A sole reference has no offset and is
not tracked, but is one of the others. Each update is a scalar Kalman
step over a random walk:

    y         = value − delta − the others' fusion
    R         = σ² + the others' fusion's σ²
    variance += track_q × hours since at
    K         = variance / (variance + R)
    delta    += K × y,  variance ×= 1 − K

A track starts at delta 0, variance (σ/2)², σ the quantity's; it starts
afresh when the location's offset for the device is relearned (another
regime, reference, constant or plain).

The alarms run on z = y / √(variance + R):

- **jumped**: `cusum_up` = max(0, `cusum_up` + z − k), `cusum_down` =
  max(0, `cusum_down` − z − k); either above h, and the track has
  jumped. It stays so until its offset is relearned or
  `Tracker#reset` drops it.
- **drifting**: |delta| above `drift_alarm` × the offset's σ; back to
  ok under `drift_clear` × σ.

| `Quantity` setting | default |
|---|---|
| `track_q` | (σ/2)² a day: σ² / 96 per hour |
| `cusum_k` (k) | 0.5 |
| `cusum_h` (h) | 5 |
| `drift_alarm` | 3 |
| `drift_clear` | 2 |

In the fusion, a tracked part's corrected value has its delta taken
out and its σ² the track's variance added; a jumped one does not count
(`jumped`), a drifting one counts (`drifting`). A track is applied only
while it tracks the offset the fusion uses.

```ruby
offsets = store.offsets("temperature")
shifts  = store.shifts("temperature")
tracker = Sensorium::Tracker.new(setup, offsets:)
tracks  = store.tracks("temperature")

# fuse, without tracks: the Tracker takes each delta out itself
fused  = Sensorium::Fusion.new(setup, offsets:, shifts:)
                          .location("green-room", snapshot)
tracks = tracker.update(tracks, fused)          # new tracks, pure
store.keep_tracks("temperature", tracks)        # replaces them all

# the value, with the tracks
Sensorium::Fusion.new(setup, offsets:, shifts:, tracks:)
                 .location("green-room", snapshot).value
```

`Tracker#update` takes a `Fused` made without tracks: one made with
them would have each delta taken out twice, and its drifting parts
would not count. `tracker.reset(tracks, "green-room", "tado")` drops a
track, which starts afresh at its next update.

The gain is small by design. In the tests' room (a sensor of
σ 0.2 °C against two of 0.1 and 0.08), ten hourly updates take delta
to 40 % of a constant bias and ten daily ones to 83 %, while a step of
3 σ is flagged jumped at the third update.

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
was heard from, or every steady reading turns stale.

## Stores

A store keeps what a learning found, the locations' settings and the
Tracker's tracks, by quantity. `Store::Memory` for tests and one-off runs;
`Store::Sequel` (`require "sensorium/store/sequel"`) for any SQL
database, its table names configurable, its tables created when missing
unless `migrate: false`. The Tracker's tracks are kept in a fourth
table (`sensor_tracks`, `tables: { tracks: }`), which a caller with
its own schema creates too. An offset's maps (switches, taus, series)
are kept as JSON. Tables made before this round lack three columns of
`sensor_offsets`: `taus` and `series` (text) and `rate` (float); a
caller with its own schema adds them. Another store answers the same
eight methods
(see `lib/sensorium/store/memory.rb`).

Keeping a learning replaces the offsets (and shifts) of the sensors it
learned again, and every offset of a location whose reference it found
changed. It leaves everything else: a sensor short of samples this
time keeps its offset, and a regime the span barely touched keeps its
model. A store's `learned` gives each regime the span of the latest
learning kept in it.

## Known shortfalls

- The fit is greedy, one term after the other; only the gain and the
  neighbour are ever fitted together.
- Only an offset's level is followed online (Tracking); its terms
  change only when learning runs again.
- A sole reference is not tracked: when it jumps, every other sensor
  of its location looks jumped.
- Until a jumped sensor's own delta has caught up, the others' deltas
  take in a little of its step (0.03 °C of 0.6 in the tests' room).
- The room preset's humidity σ and drift are first guesses, not
  measured.
- An offset of a sensor gone for good stays in the store until its
  location is learned against another reference.
- A neighbour name is "LOCATION/DEVICE": a location "a/b" with a
  device "c" and a location "a" with a device "b/c" collide.

## Gate

`bundle exec rake`: the tests, then RuboCop.
