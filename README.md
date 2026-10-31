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
               + Σ switch terms (each while its Switch is on)
               + gain × r
               + coefficient × (r - neighbour)

- **constant**: the median gap.
- **switches**: an influence that is on or off (the radiators' water
  hot, house-wide, for an hour after a valve opened).
- **gain**: the sensor reads a share too high or too low.
- **neighbour**: the sensor also follows another place: another
  location's sensor, or an external series (the outside). The one that
  fits best is chosen from the data.

Each term is kept only if it narrows the spread of what is left
(p10..p90) to 80 % of what it was. The constant alone is kept too
(`plain`), the fallback when the neighbour has no fresh reading.

A **mode** (the aircon heating or cooling) is not a term: the bins
under it, and its hold after, are left out of the fit, and each value it
takes is learned apart as a `Shift` on top of the plain offset.

Each **regime** (by default the calendar seasons) is learned apart; a
learning replaces only the regimes its span covers.

A location's **reference** is the devices its `Location` names (their
mean when several, each then learned against it too), else its first
sensor tagged with one of the setup's `places` ("ceiling", then
"floor"). A location with none is not learned.

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

Each reading is corrected to the reference with its offset, and
weighted by 1/σ²; σ grows with the reading's age (`drift` per hour),
and a reading older than `max_age` does not count. With three sensors
or more, the one furthest from the others is dropped when it is more
than 3 σ away. Notes say why a sensor does not count: `excluded`,
`stale`, `not learned`, `no context`, `outlier`. A location with no
reference gets the plain mean, `corrected` false and `sigma` nil.

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

## The source

The learner and `Snapshot.from` read the history from any object that
answers, for a quantity's name:

| method | returns |
|---|---|
| `sensors(quantity)` | `[Sensor]`: name, location, tags, whether it may be a neighbour |
| `readings(quantity, from, to, devices)` | `[Reading]`: time, location, device, value, context |
| `externals(quantity, from, to)` | `[Reading]` with location nil (optional) |
| `events(influence, from, to)` | `[[time, location, value]]` (optional) |

## Stores

A store keeps what a learning found and the locations' settings, by
quantity. `Store::Memory` for tests and one-off runs;
`Store::Sequel` (`require "sensorium/store/sequel"`) for any SQL
database, its table names configurable, its tables created when missing
unless `migrate: false`. Another store answers the same six methods
(see `lib/sensorium/store/memory.rb`).

## Known shortfalls

- The fit is greedy, one term after the other; only the gain and the
  neighbour are ever fitted together.
- No term is learned online: a model changes only when learning runs
  again.
- The room preset's humidity σ and drift are first guesses, not
  measured.

## Gate

`bundle exec rake`: the tests, then RuboCop.
