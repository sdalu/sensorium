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

The terms are chosen one after the other, each fitted on what the
ones before it left, so a term fitted early takes in some of a later
one's when their regressors move together (a Switch on while the gap
to the neighbour is wider). Once chosen, two terms or more are
refitted together, once: one least-squares regression of the gap on a
constant and each kept term's regressor (a Switch's on-state, or its
exposure at its τ; a series' value; r for the gain; r - neighbour;
dr/dt), over the bins they all cover. The refit is kept only if what
it leaves is no wider (p10..p90) than what the greedy model left over
the same bins, and it passes the scale floor below; else the greedy
model. A model with a single term is left as it is.

A correction solves the model for r, so it divides by 1 + gain +
coefficient: a gain or a neighbour (or the pair) that leaves that
below `Setup#scale_floor` (0.5) in magnitude is refused, and the model
before it kept. A neighbour coefficient of −0.9 would multiply the
sensor's noise by ten.

What the model leaves is not as wide in every state: a sensor near a
radiator is rougher while it runs, one in the sun while it shines.
Besides the spread of every bin (p10..p90), an offset keeps the spread
over the bins each Switch or Threshold kept as a term was on
(`states`, `{ name => [p10, p90] }`), and over the bins all of them
were off (`off_p10..off_p90`), and, for each series kept as a term,
over the bins its value was above its median over the fit and over the
others (`states`, `{ "name:high" => [p10, p90, median], "name:low" =>
[p10, p90, median] }`), each when it has `min_part` bins. A filtered
Switch is on over its hard hold.

The influences a `Setup` names:

| influence | told by | learned as |
|---|---|---|
| `Influence::Switch` | events, on when true or positive | a term while on (`hold` after), or × its exposure with `tau:` |
| `Influence::Series` | events with numeric values, mean per bin, carried `hold` | coefficient × value |
| `Influence::Threshold` | nothing: the location's reference, as it reads, above `above` within `hold` | a term while on |
| `Influence::Mode` | events with a value | left out, a `Shift` per value |
| `Influence::Transient` | nothing: each sensor's own series against its reference, and its transient profile | left out (`hold` after), no `Shift` |

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

### Measuring σ

An offset's spread is that of the sensor against the reference, so it
holds the reference's error as well as the sensor's. Where a location
has three series or more (its reference and two sensors learned
against it), triple collocation tells each one's own error apart,
without a truth:

```ruby
offsets      = store.offsets("temperature")
collocations = Sensorium::Collocation.learn(source, setup, from:, to:,
                                            offsets:)
store.keep_collocations("temperature", collocations)
collocations.first.sigmas   # { "ceil" => 0.11, "tado" => 0.21, ... }
```

Per location and regime, over the calm bins (no Mode held, nor within
its hold) where every series has a value (`min_samples` at least),
each sensor is corrected by its offset with what held at that bin, as
the learner read it, and the error variance of series i is the mean,
over the pairs (j, k) of the others, of cov(xᵢ − xⱼ, xᵢ − xₖ). A
negative estimate is not measurable (nil). The reference is under its
name (`"a+b"` for a mean). It assumes the series' errors independent:
an error they all share (the sun on the room, the radiators' plume)
is not seen, and an error every sensor but the reference shares is
taken for the reference's. They measure; the Fusion does not use
them (DESIGN.md, Fusion).

## Transients

A window opened, a shower, the sun on a sensor: a sudden change no
learned term explains. A sensor's **transient profile** says how far
it usually moves over a window; a change far outside it is an event.

```ruby
profiles = Sensorium::Transient.learn(source, setup, from:, to:,
                                      locations: store.locations("temperature"))
store.keep_transients("temperature", profiles)

detector = Sensorium::Transient::Detector.new(setup, profiles:)
detector.events(snapshot)
# [Transient::Event(location, device, direction (:fall or :rise), z,
#                   window, at)]
```

Per location, device and regime, for each window of
`Setup#transient_windows` (600 and 1200 s), `learn` takes the sensor's
binned series in the transform's space, carried `carry`, the bins under
a Mode or within its hold left out, and the change over the window
ending in each bin. Two `Transient::Threshold`s, each a `fall` and a
`rise`:

- **own**, of the sensor's own change: a window cools the whole room,
  so a live event is seen on the sensor itself;
- **relative**, of the change of the sensor less its location's
  reference (carried, the mean when several): only a sensor moving
  apart from its reference distorts its offset; a whole-room change,
  a radiator heating the room, does not. A reference has none.

A threshold is a quantile of the changes, set by a target rate of
false alarms, `Setup#transient_rate` (0.2 a day): the rise at
1 − rate / bins a day (144 for bins of 10 minutes), the fall at
rate / bins a day. Each window and direction leaves about that many
calm changes a day beyond its threshold. A threshold of 0 (a sensor
that almost never changes, or reports in steps) is raised to the
sensor's smallest change that is not 0, a millionth past it, so a
single step is not an event. A window seen fewer than `min_samples`
changes, or none but 0, has no threshold.

The `Detector` takes, for each sensor of a `Snapshot` with a profile
in the moment's regime, its latest reading less the one at or before
the latest's time less the window (no older than `carry` before it),
in the transform's space: a fall when the change is at or below the
own fall threshold, a rise at or above the rise threshold. An event's
`z` is the change over the threshold it went past, 1 or more (2: twice
as far). `Snapshot.from` reads the history far enough back for the
longest window and the carry (`Snapshot::Gather.reach`).

An `Influence::Transient` (name "transient", `hold` 1800 s) makes the
Learner leave transients out of the offsets. It learns the profiles
from the same span, before the offsets, and, for each sensor but the
references, puts the influence on in the bins where its relative
change over a window is beyond its relative threshold, and `hold`
after. Those bins are left out of the sensor's offset and of its
Shifts, as a Mode's are; a transient has no Shift of its own. It is
opt-in: the room preset leaves it out (DESIGN.md, Transients).

```ruby
setup = Sensorium::Presets.room
setup = setup.with(influences: setup.influences +
                                   [Sensorium::Influence::Transient.new])
```

| `Setup` setting | default |
|---|---|
| `transient_windows` | [600, 1200] s |
| `transient_rate` | 0.2 false alarms a day, per window and direction |

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
by 1/σ², σ the offset's spread / 2.563 / |1 + gain + coefficient|:
the widest of the spreads of what holds, those of the Switches kept as
its terms that are on (the spread of every bin for one without its
own), or with none on the spread while all were off, and each series'
spread at its level now (above its median, or not); an offset without
any of them, the spread of every bin. σ is never below the quantity's `floor`, grows with the
reading's age (see Staleness), and a reading older than `max_age`
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
`max_age`, the Switches on): the model stepped over the age's n
bins, in closed form, (r* − value) × (1 − (1 − a)ⁿ) toward
r* = outside + (Σ b × on + c) / a ((Σ b × on + c) × n when a is 0),
and its σ² grows by q × t, q the variance the model leaves, per
hour. Without a model for the
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

## Blending

`Blend` makes several estimates one, each with a weight the caller
gives: the temperature where people are (rooms weighted by how
occupied they are), a floor's (its rooms by area), a house's. The
estimates are keyed by whatever the caller names them, and are
anything answering `value` and `sigma`: a `Fused`, an `Estimate`, a
`Blended`.

```ruby
rooms   = fusion.locations(snapshot).to_h { [it, fusion.location(it, snapshot)] }
blended = Sensorium::Blend.new({ "downstairs" => 0.8, "green-room" => 0.2 })
                          .of(rooms)
blended.value     # the weighted mean
blended.sigma     # √Σ (w / W)² σ², nil if one that counts has none
blended.shares    # { key => Share(weight, value, sigma) }
```

Weights are a Hash (missing keys weigh 0) or anything answering
`call(key)`; a weight below zero is refused. An estimate without a
value does not count, the others' shares filling its place; with no
weight anywhere there is no value, and the caller chooses what stands
in (equal weights give the plain mean). Estimates that say their
quantity must say the same one; `at` is the latest they say.

## Tracking

Between two learnings an offset can move: a sensor moved, re-batteried
or ageing reads wrong until the next learning. The `Tracker` follows,
for each sensor with an `Offset` and for each reference, a `Track`: `delta`, its corrected
value minus the truth, as estimated, with its `variance`; the two sides
of a CUSUM; `at`, the time of its last update; and a `state`, `:ok`,
`:drifting` or `:jumped`.

The truth, for one part of a `Fused`, is the `Combine.robust` fusion
of the other parts that count (a value and a σ, no note but
`outlier`), each with its own delta taken out, less those whose track
has jumped, before or in this update. The references are updated
first, then the other parts, each in the `Fused`'s order. A part with
fewer than two others is left as it was, unless a **witness** stands
in for the second (below). Each update is a scalar Kalman step over a
random walk:

    y         = value − delta − the others' fusion
    R         = σ² + the others' fusion's σ²
    variance += track_q × hours since at
    K         = variance / (variance + R)
    delta    += K × y,  variance ×= 1 − K

A track starts at delta 0, variance (σ/2)², σ the quantity's; it starts
afresh when the location's offset for the device is relearned (another
regime, reference, constant or plain). A reference's track is pinned:
the references are the anchor, so its delta stays 0 and its variance
(σ/2)²; only its CUSUM runs, and it may jump, never drift. Its
fingerprint is the regime and the location's references ("a+b"),
constant and plain nil.

The alarms run on z = y / √(variance + R):

- **jumped**: `cusum_up` = max(0, `cusum_up` + z − k), `cusum_down` =
  max(0, `cusum_down` − z − k); either above h, and the track has
  jumped. It stays so until its offset is relearned or
  `Tracker#reset` drops it.
- **drifting**: |delta| above `drift_alarm` × the offset's σ; back to
  ok under `drift_clear` × σ. Not for a reference.

| `Quantity` setting | default |
|---|---|
| `track_q` | (σ/2)² a day: σ² / 96 per hour |
| `cusum_k` (k) | 0.5 |
| `cusum_h` (h) | 5 |
| `drift_alarm` | 3 |
| `drift_clear` | 2 |

In the fusion, a tracked part's corrected value has its delta taken
out and its σ² the track's variance added; a jumped one does not count
(`jumped`), a drifting one counts (`drifting`). A jumped reference
does not count either; the other sensors' corrections stay as they
are, their offsets telling what the reference reads when healthy. A
track is applied only while its fingerprint is the moment's.

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

In a location of three, a jumped part leaves each other one with a
single other. Given the location's dynamics (see Staleness), the
previous `Fused` (made *with* the tracks, so its jumped parts were
already out) and the snapshot the current one was made from, the
Tracker makes a witness: the previous value moved by the model to the
moment, as an aged reading is, with the moment's inputs (the outside,
the Switches on), its σ² the previous one's plus q × the hours since.
It counts as one more other for a part that has a single one. There is
none without a model for the location and the moment's regime,
without the outside its model needs, while a Mode holds there, or
when the previous `Fused` has no value or σ, or is older than the
location's `max_age`; the part is then left as it was.

Given transient profiles (`transients:`, see Transients) and the
snapshot the `Fused` was made from, the Tracker leaves every part of a
location as it was while the `Detector` finds an event there at the
moment, as it leaves a part with too few others: an opened window
would read as a step and could push a CUSUM to a `jumped` that sticks
until a relearn. Without profiles or snapshot, it tracks as before.

```ruby
tracker  = Sensorium::Tracker.new(setup, offsets:,
                                  dynamics: store.dynamics("temperature"),
                                  locations: store.locations("temperature"),
                                  transients: store.transients("temperature"))
tracks   = tracker.update(tracks, fused, previous:, snapshot:)
previous = Sensorium::Fusion.new(setup, offsets:, shifts:, tracks:)
                            .location("green-room", snapshot)
```

The gain is small by design. In the tests' room (a sensor of
σ 0.2 °C against two of 0.1 and 0.08), ten hourly updates take delta
to 40 % of a constant bias, 48 hourly ones to 88 % and ten daily ones
to 80 %, while a step of 3 σ is flagged jumped at the third update,
and the reference stepping by 5 σ at the second.

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

A store keeps what a learning found, the locations' settings and the
Tracker's tracks, by quantity. `Store::Memory` for tests and one-off
runs; `Store::Sequel` (`require "sensorium/store/sequel"`) for any SQL
database, its table names configurable, its tables created when
missing unless `migrate: false`. The Tracker's tracks, the dynamics
models, the collocations and the transient profiles are kept in four
more tables (`sensor_tracks`, `tables: { tracks: }`;
`sensor_dynamics`, `tables: { dynamics: }`; `sensor_collocations`,
`tables: { collocations: }`; `sensor_transients`, `tables: {
transients: }`), which a caller with its own schema creates too, as
`Store::Sequel::Schema` does. An offset's maps (switches, taus,
series, states) are kept as JSON, as are a location's `deltas`, a
dynamics model's `b`, a collocation's `sigmas` and a profile's `own`
and `relative` thresholds (`{ "600": [fall, rise] }`). Tables made before
the survey rounds lack six columns of `sensor_offsets`: `taus`,
`series` and `states` (text), `rate`, `off_p10` and `off_p90` (float),
and `sensor_locations` lacks `deltas` (text); a caller with its own
schema adds them. Another store answers the same fifteen methods (see
`lib/sensorium/store/memory.rb`).

Keeping dynamics (`keep_dynamics`) or collocations
(`keep_collocations`) replaces those of the same location and regime,
and leaves the others; keeping transient profiles
(`keep_transients`), those of the same location, device and regime.

Keeping a learning replaces the offsets (and shifts) of the sensors it
learned again, and every offset of a location whose reference it found
changed. It leaves everything else: a sensor short of samples this
time keeps its offset, and a regime the span barely touched keeps its
model. A sensor the source no longer lists (gone from `sensors`) is
dropped, its offsets and shifts in every regime; `forget(quantity,
location, device)` drops one on demand, its track and transient
profiles too. A store's
`learned` gives each regime the span of the latest learning kept in
it.

## Known shortfalls

- A gain refitted with other terms is a least-squares one, biased
  toward zero by about σ²/var(r), as the gain of a gain and neighbour
  pair is; only a gain alone is a Deming line.
- Only an offset's level is followed online (Tracking); its terms
  change only when learning runs again.
- Until a sensor is flagged jumped, the others' deltas take in a
  little of its step (0.008 °C of 0.6 in the tests' room).
- In a location of three with a jumped sensor, the witness is made
  from the two others: a bias on one of them is shared between their
  deltas. In the tests' room, 48 hourly updates take tado's delta to
  60 % of a 0.2 bias while Airzone's moves by −0.075. Without
  dynamics, their tracks stand still until a relearn or a reset.
- The room preset's humidity σ and drift are first guesses, not
  measured: triple collocation needs three humidity series in a
  location.
- The fused σ still assumes the parts' errors independent: an error
  they share (the reference's, the sun, a radiator's plume) is not in
  it, and neither triple collocation nor a leave-one-out on the same
  data can see one (DESIGN.md, Fusion). The collocations are learned
  and kept but not used by the Fusion.
- The per-state spreads cover the Switches, Thresholds and Series,
  not the Modes (a Shift has its own spread).
- A dynamics model's q is calibrated on the span it was fitted on:
  another season may move more, or less.
- A blend takes its estimates' errors as independent.
- A transient threshold is learned from all the calm changes of a
  regime, the transients the Detector should find among them: a
  sensor aired every winter morning learns its airings as its usual
  changes. On one house's green-room (a year of profiles, 74 window
  openings on cold days, rate 0.2), tado alone finds 92 % of the
  openings with some 0.33 false alarms a day (a fixed rule, tado
  falling 0.5 °C in ten minutes: 92 %, 0.10); two sensors agreeing,
  88 % at 0.07.
- The rate holds per window and direction: a sensor with two windows
  may raise up to four times as many false alarms a day, fewer as its
  windows overlap.

## Gate

`bundle exec rake`: the tests, then RuboCop.
