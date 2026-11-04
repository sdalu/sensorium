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

For every sensor of a location, bin by bin (`Setup#bin`, 10 minutes by
default), the learner
models the gap to the location's reference r:

```text
sensor - r = constant
           + Σ switch terms (each while its Switch is on,
                             or × its exposure when filtered)
           + Σ series coefficients × their values
           + gain × r
           + coefficient × (r - neighbour)
           + rate × dr/dt
```

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
  A column that does not vary (a frozen reference) has no slope:
  `Stats`' `line`, `plane` and `least_squares` answer nil when a
  column's range is within rounding (1e-9) of its size
  (`Stats.constant?`): a frozen sensor's bin means, sums of ten
  readings or eleven divided, differ by an ulp.
- **neighbour**: the sensor also follows another place: another
  location's sensor, or an external series (the outside); or, with a
  coefficient above 0, the neighbour stands in for what drives the
  sensor's error. The one that fits best is chosen from the data.
- **rate**: the sensor is slower than the reference and lags it on
  every change (dr/dt per hour, `Setup#rate`).

Each term is kept only if it narrows the spread (p10..p90) of the
correction to 80 % of what it was, both measured over the bins the
term covers: what the model leaves over |1 + gain + coefficient|, the
scale a correction divides by (`Fit::Model#scale`, below). A neighbour
with a coefficient of −0.4 that narrows the gap to 70 % widens the
correction to 117 % and is refused; one of +0.6 that narrows the gap
to 90 % narrows the correction to 56 % and is kept. The terms are
chosen without the last tenth of a sensor's bins (100 at least,
`min_part`), and a term is kept only if those bins confirm it, their
correction's spread measured the same way: when what it adds varies
over them by more than the rounding (its range, max − min, above
1e-9: a neighbour, a series, a Switch on in a few of them, which
switches there), it must leave them no wider than the model before
it; when it adds a
constant there (a Switch never on in them, or on throughout), they
cannot tell, and it must leave them no more than 5 % wider. The terms
kept are then fitted again on all the bins.

```text
a term tried, against the model before it

               p10..p90 of the correction, what the model leaves
               over |1 + gain + coefficient|, at both steps

bins fitted    narrows p10..p90 to 80 %? ── no ──▸ refused
                            │ yes
last tenth     what it adds varies there?
held out       (its range above 1e-9)
                            │
                 yes ┌──────┴──────┐ no: it adds a constant
                     │             │
                 no wider      within 5 %
                 (≤ 1.00)      (≤ 1.05)
                     │             │
                     └──────┬──────┘
                            ▾
               kept if it passes, else refused
```

What the terms narrow is measured on the bins they were chosen
on, and those overstate it: a sensor's error persists for hours, so a
season holds far fewer independent bins than it has. The narrowing of
the plain constant's spread the refit on all the bins claims is set
against the one the bins held out confirm, and when those confirm
less, every width of the model (p10..p90, those of `states`,
`off_p10..off_p90`) is widened about its middle by the ratio: its σ is
the plain constant's narrowed by what the bins it never saw bear out,
and never wider than the plain constant's, both taken as corrected
(over |1 + gain + coefficient|), the way a width is used.
A sensor with too few bins to hold any out keeps the constant alone.
The constant alone is kept too (`plain`, its widths as fitted), the
fallback when the neighbour, a series' value or dr/dt has no fresh
value.

```text
inflation = max(1, min(narrowing held out, scale)
                   / narrowing the refit claims)
scale     = |1 + gain + coefficient|, the plain constant's 1

                 p10         middle          p90
as fitted         ├─────────────┼─────────────┤
widened      ├──────────────────┼──────────────────┤
             each half × inflation, about the middle

p10..p90, each state's and off_p10..off_p90 are widened;
plain_p10..plain_p90, the plain constant's, never are
```

An Offset also keeps its `block_share`: the spread of what its model
leaves, averaged over blocks of the quantity's `cusum_block` (3 h;
whole blocks, those holding half their bins at least, the same for a
`cusum_block` given as a Float), as a share of its spread bin by bin;
about 1/√18 if the bins were
independent, near 1 for a sensor whose error persists for hours
(0.82 and 0.85 for the two of a room recorded over a winter). The
Tracker standardises a block's mean innovation by it (see Tracking).

```text
what the model leaves, bin by bin (10 minutes), and its mean
over each block of 3 hours (illustrative)

               ├─── 18 bins ────┤  ├─── 18 bins ────┤
independent    ▅▂▇▁▆▃▄▇▂▅▁▆▃▇▂▄▆▁  ▄▆▁▅▃▇▂▄▆▂▅▇▁▃▆▂▄▅
  block mean   ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄  ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄  ≈ 1/√18
persistent     ▁▂▁▂▂▁▂▃▂▂▃▂▂▃▂▂▃▂  ▆▇▆▇▇▆▇▇▆▇▇▆▇▆▇▇▆▇
  block mean   ▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂  ▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇  near 1
```

The terms are chosen one after the other, each fitted on what the
ones before it left. The room preset tries neither a gain nor a rate
term (`gain: false`, `rate: false`): no sensor of the house it was
measured on kept either; `Presets.room(gain: true, rate: true)` puts
them back.

A correction solves the model for r, so it divides by 1 + gain +
coefficient (`Offset#correct`), and so does what it leaves: the keep
tests above judge that, not the gap. A gain or a neighbour (or the
pair) that leaves the scale below `Setup#scale_floor` (0.5) in
magnitude is refused, and the model
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

The influences a `Setup` names, each told by what follows its name and
learned as what follows the arrow:

- `Influence::Switch`: events, on when true or positive → a term while
  on (`hold` after), or × its exposure with `tau:`. A text value is
  trimmed: a number is read as its number, "off" and "false" in any
  case are off (`Influence::Switch::OFF`), and any other text, "no"
  and "" included, is on.
- `Influence::Series`: events with numeric values, mean per bin,
  carried `hold` → coefficient × value.
- `Influence::Threshold`: nothing; the location's reference, as it
  reads, above `above` within `hold` → a term while on.
- `Influence::Mode`: events with a value, held `hold` after → left
  out, a `Shift` per value (two Modes at once: one value).
- `Influence::Transient`: nothing; each sensor's own series against its
  reference, and its transient profile → left out (`hold` after), no
  `Shift`.

```ruby
solar   = Sensorium::Influence::Series.new(name: "solar", hold: 1800)
heating = Sensorium::Presets::HEATING
              .with(tau: Sensorium::Influence::TAUS)
setup   = Sensorium::Presets.room.with(
    influences: [heating, Sensorium::Presets::AIRCON, solar]
)
```

The bin is a setting (`Presets.room(bin: 300)`): the counts given in
bins (`min_samples`, `min_shift`, `min_part`) then cover the same time
as their defaults do at ten minutes, and the transient windows are one
bin and two, unless given; a window not a whole number of bins is
refused. `Setup#with` and `Quantity#with` rebuild from the arguments
first given plus the changes, so what is derived and was not given
(the counts and windows from the bin, `floor` and `track_q` from σ)
is derived again (`Presets.room.with(bin: 900)` takes windows of 900
and 1800 s); with no change, they answer the same object. A `Tick`
need not run once a bin: it fuses the latest reading of each sensor
at the moment it is called.

A **mode** (the aircon heating or cooling) is not a term: the bins
under it, and its hold after, are left out of the fit, and each value it
takes is learned apart as a `Shift` on top of the plain offset, over
the bins it held, its hold after included: those the Fusion takes it
as holding, the hold counted from the event, not from the bin the
event fell in (as for a Switch's). Two Modes holding at once are a
value of their own: each Shift is learned over the bins its Mode held
alone, and the pair's
over the bins both held, named by both (influence "aircon+fan", mode
"cooling+on"); what two do together is not the sum. A value held
fewer than `min_shift` bins has no Shift.

Each **regime** (by default the calendar seasons) is learned apart.
The room preset's months are one climate's heating season (winter
Nov–Mar, mid Apr, May and Oct, summer Jun–Sep): elsewhere, set them
with `Regime::Calendar.new(months)`, months `{ name => [month] }`,
every month in one, given as the `Setup`'s `regime`
(`Presets.room.with(regime: Sensorium::Regime::Calendar.new(...))`).
The months are the site's, in the process's local zone, whatever the
time's own: with TZ Europe/Paris, 2026-03-31T22:30Z is April, "mid",
for learning and fusion alike. A regime is asked of local times
everywhere: the History of `Time.at(bin)`, and the Fusion, the
Detector and the Tracker of the snapshot's moment taken local, so a
regime of one's own (anything answering `names`, `of(time)` and
`covered(from, to)`) sees the same zone throughout.

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
negative estimate is not measurable (nil), and nor is any with fewer
than three columns, which give no pairs. A sole reference is a
series as it reads, under its name; several are each corrected to
their mean by their offset, and the mean, made of them, is not a
series beside them. It assumes the series' errors independent:
an error they all share (the sun on the room, the radiators' plume)
is not seen, and an error every sensor but the reference shares is
taken for the reference's. The Fusion takes one of them only: a sole
reference's σ (see Fusing); every sensor keeps its offset's σ
(DESIGN.md, Fusion).

## Transients

A window opened, a shower, the sun on a sensor: a sudden change no
learned term explains. A sensor's **transient profile** says how far
it usually moves over a window; a change far outside it is an event.

```ruby
locations = store.locations("temperature")
profiles  = Sensorium::Transient.learn(source, setup, from:, to:,
                                       locations:)
store.keep_transients("temperature", profiles)

detector = Sensorium::Transient::Detector.new(setup, profiles:,
                                              locations:)
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
single step is not an event. A threshold that several changes sit at
(a sensor reporting in steps) moves a millionth past them too, when
leaving them out of those beyond comes nearer the rate than counting
them; a quantile no other change ties keeps its value exactly.
Changes are compared rounded to nine decimals
(`Transient::DIGITS`), so one step read as floats a few ulps apart is
one change, and a tie made by float noise is a tie; a raise is
max(|v| × 1e-6, 2e-9) past the value v it moves from, so it
survives that rounding.
A window seen fewer than `min_samples`
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
Learner leave transients out of the offsets. It takes the profiles
given (`transients:`), else learns them from the same span, before the
offsets, and, for each sensor but the
references, puts the influence on in the bins where its relative
change over a window is beyond its relative threshold, and `hold`
after. Those bins are left out of the sensor's offset and of its
Shifts, as a Mode's are; a transient has no Shift of its own. It is
opt-in: the room preset leaves it out (DESIGN.md, Transients).

```ruby
transient = Sensorium::Influence::Transient.new
setup     = Sensorium::Presets.room
setup     = setup.with(influences: setup.influences + [transient])
```

| `Setup` setting     | default                                        |
| ------------------- | ---------------------------------------------- |
| `transient_windows` | [600, 1200] s                                  |
| `transient_rate`    | 0.2 false alarms/day, per window and direction |

## Fusing

```ruby
snapshot = Sensorium::Snapshot.from(source, setup, at: Time.now)
fusion   = Sensorium::Fusion.new(
    setup,
    offsets: store.offsets("temperature"),
    shifts: store.shifts("temperature"),
    locations: store.locations("temperature"),
    collocations: store.collocations("temperature")
)
fused = fusion.location("green-room", snapshot)
fused.value       # °C, corrected to the reference
fused.sigma       # one σ
fused.parts       # each sensor: raw, corrected, weight, note
```

Each reading is corrected to the reference with its offset (while a
Mode holds, its latest value within its hold, with the plain offset
and the Shift of exactly what holds: one Mode's value, or two Modes'
as one; with no Shift learned for it, the plain offset alone and its
plain σ, as for any input not known), given what holds at the moment:
the switches and thresholds on, a filtered switch's exposure over the
5 τ before, each series' latest value within its hold, and dr/dt
from the reference's two latest readings within `max_age`
(`Snapshot#history`). Without a series' value or dr/dt, the plain
offset. Each reading is weighted by 1/σ², σ the
offset's spread / 2.563 / |1 + gain + coefficient|: the widest of the
spreads of what holds, those of the Switches kept as its terms that
are on (the spread of every bin for one without its own), or with none
on the spread while all were off, and each series' spread at its level
now (above its median, or not); an offset without any of them, the
spread of every bin. σ is never below the quantity's `floor`, grows
with the reading's age (see Staleness), and a reading older than
`max_age` does not count. A location without references set takes
those it was learned against in the moment's regime. A reference is
weighted by the location's σ: the one its `Location` sets; else, for
a sole reference its `Collocation` measured in the moment's regime
(`collocations:`), that σ, no lower than the quantity's `floor` and no
higher than the tightest σ of the corrections to it (each holds the
reference's error); else (several references, no collocation, or one
that could not measure it) the quantity's. With three
sensors or more, the inverse-variance fusion is Student-t reweighted
(ν `robust_nu`) until it settles, the value moving less than 1e-6;
past `Combine::STEPS` (1000) the steps are crawling, near where a far
part's pull gives way, and the crawl is taken through at once, to the
fixed point the steps were nearing or past a bottleneck with none (no
fusion of the house's year crawls; about one random three-part fusion
in 150 000 does): a part far
from the rest counts for less, smoothly, rather than one furthest
part being dropped outright. A part whose final weight falls below
the quantity's `outlier_factor` share of 1/σ² is noted `outlier`, but
still counts for that little. With two, there is no majority to call
either an outlier: the fusion is the inverse-variance one, and its σ
is widened by how far the two disagree in their joint σ, never
narrowed:

```text
σ = σ inverse-variance × max(1, |a − b| / √(σa² + σb²))

        a ± σa                    b ± σb
  ──────●───────────────────────────●──────
        ├──────── |a − b| ──────────┤
  within √(σa² + σb²): σ as it is; beyond: × the ratio
```

Notes say why a sensor does not count: `excluded`, `stale`, `not
learned`, `no context`, `jumped` (its track says so, see Tracking), or
that it counts with a caveat: `outlier`, `drifting` (its track says
so). A location with no reference gets its readings as they read,
weighted by 1/σ², each σ the location's (the quantity's by default)
grown with the reading's age: `corrected` false.

### Which readings a fusion takes

A fusion at a moment T takes, for each sensor, the reading with the
latest time at or before T: the time the source gives it, the time it
was measured, not when it reached the source. `Snapshot.from` asks the
source for the readings of the three hours before T, and the Fusion
leaves out those older than `max_age` (60 minutes by default). In a
room of three sensors (illustrative numbers):

```text
time      10:00   10:02   10:05   10:07   10:10
            |       |       |       |       |
ceiling     ●───────────────────────●              every ~7 min
           21.3                    21.4
wall        ●───────────────●───────────────●      every 5 min
           20.6            20.7            20.8
valve       ●                                      every ~12 min
           20.1
                                            ▲
                                    fusion at 10:10

            read   offset   corrected   age      weight
ceiling     21.4    0.0      21.40      3 min    high (reference)
wall        20.8   −0.6      21.40      0 min    medium
valve       20.1   −1.1      21.20     10 min    low (older, noisier)
                             fused 21.35 ± 0.08 at 10:10
```

An older reading is not dropped but brought to the moment: its value
as it is, its σ widened with its age (see Staleness), so it counts for
less. A fused value is the estimate at its moment, not over the
interval before it:

```text
age of the reading     in the fusion
0 min                  its full weight
12 min                 its σ widened with its age
over max_age           left out (stale)
```

How often to fuse is the caller's: once a bin, or each time a reading
arrives. Neither is behind; the second gives a value more often.

```text
readings   ●   ●   ●   ●     ●   ●    ●     ●   ●
timer      ■            ■            ■            ■     every 10 min
on arrival ■   ■   ■   ■     ■   ■    ■     ■   ■     after each reading
```

A reading that reaches the source late, at its own (earlier) time, is
taken by the next fusion if it is still its sensor's latest and within
`max_age`; a fusion already made is not revised, and the learning,
which reads the history by time, has it in its place:

```text
valve measures  10:08 ●
source has it   10:13 ■  at 10:08

fusion 10:10    not there yet: valve @10:00
fusion 10:20    valve @10:08, 12 min old
```

The order readings arrive in does not matter, only their times: a late
reading older than one already there is not its sensor's latest, and
the newer one is fused.

### Staleness

A reading is an estimate of the reference when it was taken; by the
time it is fused, the room has moved on. Its σ grows with its age t
(hours) as √(σ² + (drift × t)²), its value unmoved: the drift rule,
`drift` the location's (the quantity's by default).

A **send-on-delta** sensor reports only when its value moved by a
threshold: an unchanged value is within that delta of the truth as
long as the sensor is alive. A `Location`'s `deltas` (`{ device =>
delta }`, as the quantity reads, before the transform) cap what the
age adds to σ² at delta² / 3; the delta is
taken into the transform's space at the reading (2 %RH is some
0.35 g/m³ at 20 °C). `max_age` still cuts: a sensor silent for longer
may be dead.

```ruby
store.set_location("temperature", "green-room",
                   { deltas: { "hue-1" => 0.2 } })
```

### Dynamics

A location's **dynamics** are a toolkit for a caller that wants to
predict its reference, such as a heating planner: a first-order model
of the reference r over one bin, per regime,

```text
r(t + bin) - r(t) = a × (outside - r) + Σ b[switch] × on + c + noise
```

with `outside` the external series `Setup#outside` names (none: a is
0) and `on` 1 while each Switch is on (its hard hold, not its
exposure). A `Dynamics::Model` gives the change it predicts over some
hours from a value and the inputs (`change(value, outside, on,
hours)`): the model stepped over the hours' n bins, in closed form,
(r* − value) × (1 − (1 − a)ⁿ) toward
r* = outside + (Σ b × on + c) / a ((Σ b × on + c) × n when a is 0),
nil without the outside when a ≠ 0; and the variance its noise adds
(`variance(hours)`, q × hours, q per hour). The Fusion does not use
the models: an old reading ages by the drift rule (DESIGN.md,
Staleness).

```ruby
setup = Sensorium::Presets.room.with(outside: "outside")
models = Sensorium::Dynamics.learn(source, setup, from:, to:)
store.keep_dynamics("temperature", models)
store.dynamics("temperature")     # [Sensorium::Dynamics::Model]
```

`Dynamics.learn` takes the location's reference as the learner does
(the `Location`'s, else the setup's `places`), fits the model by least
squares over the steps of the carried reference series where every
term is known, a step left out when its start bin or its end bin is
one where a Mode held, or held within its hold (the step into a
Mode's first bin takes in its onset), and gives no model for
a location and regime seen less than `min_samples` steps, or with
a < 0 (a room running away from the outside is not a model). A Switch
never off, or never on, in a regime is left out: its term cannot be
told from c. q is the mean square of the error of predicting the
reference an hour ahead (`Dynamics::Forecast`), over the bins fitted;
a forecast counts only when every bin of its span, start to target,
is free of a Mode (the aircon's hold, 1800 s, is shorter than the
two-hour horizon below). `Dynamics::Forecast.new` takes, after the
reference, the outside and the Switches on, an optional `near`,
answering `call(bin)` with whether a Mode held there or within its
hold (none: never). A horizon is whole bins, one at least: with a
bin that does not divide an hour (480 s), an hour ahead is the
nearest whole number of bins (eight, 64 minutes).

What the caller knows of a room beforehand can be given as a prior:
`priors:` maps a location to a `Dynamics::Prior` (or answers
`call(location, regime)` with one), its `a`, `c` and each `b` a
`[mean, σ]`. A time constant τ in hours is a = bin / (τ × 3600). The
fit adds each prior's precision to the data's, so a loose prior gives
way to a long history and a tight one holds where the history is thin;
the validation fits with the same prior. Where a prior comes from (a
building's walls and volume, another room, a past year) is the
caller's.

```ruby
prior  = Sensorium::Dynamics::Prior.new(a: [600.0 / (40 * 3600), 0.002])
models = Sensorium::Dynamics.learn(source, setup, from:, to:,
                                   priors: { "green-room" => prior })
```

Each model is validated: fitted without the last tenth of its steps
(a week at least), it must predict the reference two hours ahead
(in whole bins, as above) from
those steps with an RMS error at most `Setup#dynamics_margin` (98 %)
of holding the last value's, or the
location and regime get no model; kept, it is fitted again on all its
steps and carries both errors (`rms_hold`, `rms_model`). It is learned
apart from `Learner#learn`, so a caller can run it on its own schedule.

## Predicting

The other way round: the reading a sensor is expected to give while
its location's reference is r, for a caller that sends a device the
setpoint its own sensor reads when the room is at its target.
`Offset#predict(r, ...)` takes what `correct` takes and states the
model forward (r × scale − k × neighbour + constant + switched + fed +
rate × dr/dt), with the same fallback: while a Mode holds, or when an
input is not known, r + plain + the Shift. `correct` is its inverse.
Its σ is the spread of what the model leaves, a reading's own: a
correction's is over scale, a reading's is not, and r is taken as
exact (the target is). A `Knowledge` finds the facts:

```ruby
knowledge = store.knowledge("temperature")   # a store opened read-only
regime    = setup.regime.of(at)              # local months
offset    = knowledge.offset(location, "tado", regime) or return
holding   = []              # an Airzone: [%w[aircon heating]]
shift     = knowledge.shift(location, "tado", regime, holding)
reading   = offset.predict(target, shifts: [shift].compact,
                                   held: holding.any?, on: %w[heating],
                                   neighbour: nil, dr_dt: 0.0)
track     = knowledge.track(location, "tado", offset)
reading   = track.foresee(reading) if track  # nil while jumped
```

`Knowledge#shift` names what holds as one value (`Shift.named`); a
Mode holding without a Shift is still held (`held: true`).
`Knowledge#track` answers the sensor's Track while it follows that
Offset (nil after a relearn), and `Track#foresee` puts its delta
back, `apply`'s inverse, its variance added; nil while jumped: the
sensor's reading is then not known. A neighbour is one named device
(`LOCATION/DEVICE`), not the fused value: without its reading, pass
nil and take the plain offset. While a device regulates, a tado's
heating is the site Switch on; an Airzone's is its Mode holding,
which its Shift was learned over.

On one house's year, learned month by month and predicted over the
month after, while a device regulated with the reference steady, the
reading came within the σ stated on four of five winter sensors with
their valve working (residual −0.22 to +0.07 °C, var(z) 0.45 to 1.13)
and on the Airzones under their heating Mode (var(z) 0.55 and 1.05);
not on a noisy tado (var(z) 4.6), nor while the reference moves (a
steady state is what is predicted). An Offset not learned yet in a
regime (a season's first month) gives no prediction.

## Relearning

The four learners read the same span: the `Learner` (offsets and
shifts), `Dynamics.learn`, `Collocation.learn` and `Transient.learn`.
A `History` reads it from the source once, the readings in one call
and each influence's events in one, and each learner takes it as
`history:`; without it, each loads its own, as above. It holds the
sensors, the references, the binned series in the transform's space
(the sensors, the references set, the externals) and the influences'
timeline, and finds each location's carried reference series and its
rate once, for all four. Given the profiles (`transients:`), the
Learner does not learn them again for an `Influence::Transient`.

```ruby
locations = store.locations("temperature")
history   = Sensorium::History.load(source, setup, from:, to:,
                                    locations:)
profiles  = Sensorium::Transient.learn(source, setup, history:)
learned   = Sensorium::Learner.new(source, setup, history:,
                                   transients: profiles).learn
models    = Sensorium::Dynamics.learn(source, setup, history:)
collocations = Sensorium::Collocation.learn(source, setup, history:,
                                            offsets: learned.offsets)
```

## Blending

`Blend` makes several estimates one, each with a weight the caller
gives: the temperature where people are (rooms weighted by how
occupied they are), a floor's (its rooms by area), a house's. The
estimates are keyed by whatever the caller names them, and are
anything answering `value` and `sigma`: a `Fused`, an `Estimate`, a
`Blended`.

```ruby
rooms   = fusion.locations(snapshot)
                .to_h { [it, fusion.location(it, snapshot)] }
weights = { "downstairs" => 0.8, "green-room" => 0.2 }
blended = Sensorium::Blend.new(weights).of(rooms)
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
for each sensor with an `Offset` and for each reference, a `Track`:
`delta`, its corrected value minus the truth, as estimated, with its
`variance`; the two sides of a CUSUM; the block of readings under way
(the sum of their innovations and of their noise, their count, and
`block_at`, the time of its first); `at`, the time of the reading its
last update took (the reading's own, which its `Part` carries); and a
`state`, `:ok`, `:drifting` or `:jumped`.
A part is updated only when its reading is newer than that: fused
again before the sensor reads again, it is left as it was, so the
tracks are the same whether a location is fused every minute or at
each reading, and a reading never counts twice in a CUSUM.

The truth, for one part of a `Fused`, is the `Combine.robust` fusion
of the other parts that count (a value and a σ, no note but
`outlier`), each with its own delta taken out, less those whose track
has jumped, before or in this update, and less the **suspect**: the
part whose CUSUM is the highest once past half of h, the block under
way counted in full (a suspect is left out, not flagged, and is back
once its CUSUM falls), left out of every
other part's truth (not its own), so that a step not yet flagged leaks
into no other delta. There is a suspect only among three tracks or
more that have not jumped: with two, no majority tells which is off.
The references are updated first, then the other parts, each in the
`Fused`'s order. A sensor whose single other is a reference is
updated against it alone: its `Offset` was learned on that pair, and
the reference's delta is pinned at 0, so their disagreement is the
sensor's. Any other part with fewer than two others (a reference with
a sensor alone, two sensors without their reference, two references)
is left as it was.

```text
a room of four, ceil the reference; wall's CUSUM is the highest,
and past half of h: wall is the suspect

part        its truth, the others' fusion of
ceil        tado, Airzone          wall left out
wall        ceil, tado, Airzone    it still updates
tado        ceil, Airzone          wall left out
Airzone     ceil, tado             wall left out
```

In a room of three, a part out (a suspect, a jump) leaves the two
others with one each, and a room of two has no more:

```text
ceil the reference; each part, its others, and whether its track is
updated

                  part   its others   updated
room of three     ceil   wall, tado   yes
                  wall   ceil, tado   yes
                  tado   ceil, wall   yes

wall the suspect  ceil   tado         no: a sensor alone
                  wall   ceil, tado   yes
                  tado   ceil         yes: against its reference

tado jumped       ceil   wall         no: a sensor alone
                  wall   ceil         yes: against its reference
                  tado   ceil, wall   the return test

ceil jumped       ceil   wall, tado   the return test
                  wall   tado         no: two sensors
                  tado   wall         no: two sensors

room of two       ceil   wall         no: a sensor alone
                  wall   ceil         yes: against its reference
```

A sensor's error persists for hours (the sun on a wall, a radiator's
cycle), so its successive innovations are not independent: counted one
by one, they would teach delta, and push a CUSUM, as if each were news.
The Tracker takes them by blocks of `cusum_block` (3 h): each reading
walks the variance and joins the block under way; once the block
spans 3 h, its mean is one measurement, its noise the mean one's times
the Offset's `block_share` squared (see Learning: what the model's
error keeps when averaged over a block, near 1 for a sensor whose error
persists, 1/√n for independent bins; 1 when unknown), and delta takes
one scalar Kalman step over a random walk:

```text
y         = value − delta − the others' fusion       (each reading)
R         = σ² + the others' fusion's σ²
variance += track_q × hours since at
ȳ, R̄      = the block's mean y and mean R             (block closed)
S         = variance + block_share² × R̄
K         = variance / S
delta    += K × ȳ,  variance ×= 1 − K
```

So delta learns as fast at any cadence, and the alarms see each block
before delta takes it in. A reading that finds its block spanning 3 h
closes it first, then is measured against the delta that block taught,
and opens the next:

```text
time      0:00   0:50   1:40   2:30   3:10   4:00
reading    ●      ●      ●      ●      ●      ●
           └───── block 1 ──────┘      └─── block 2 ────
           block_at 0:00               block_at 3:10

at 3:10, in this order:
  1. the variance walks: + track_q × hours since 2:30
  2. 3:10 − block_at ≥ 3 h: block 1 is closed, its mean to the
     CUSUM, then one Kalman step moves delta
  3. the 3:10 reading's y, against the delta block 1 taught
  4. the reading opens block 2
```

A track starts at delta 0, variance (σ/2)², σ the quantity's; it starts
afresh when the location's offset for the device is relearned (another
regime, reference, constant or plain). A reference's track is pinned:
the references are the anchor, so its delta stays 0, a convention,
and its variance (σ/2)², the fresh prior, which never moves; only its
CUSUM runs, and it may jump, never drift. Neither is an estimate, so
the Fusion adds neither to a reference's σ (below). What the
Tracker sees of a reference is its disagreement with the room, which
is usually as wide as the room's sensors' spread against it, not its
instrument's σ: its innovations are judged with the smallest σ of the
location's Offsets (the tightest bounds the reference's own
excursions), or with its own σ (the location's, see Fusing) where
that is wider, and its block means are standardised by
the largest `block_share` of those Offsets. Its fingerprint is the
regime and the location's references ("a+b"), constant and plain nil.

The alarms:

- **jumped**: at each closed block, with z̄ = ȳ / √S, `cusum_up` =
  max(0, `cusum_up` + z̄ − k), `cusum_down` = max(0, `cusum_down` − z̄ −
  k); either above h, and the track has jumped. The block under way
  counts too, as if it closed now, its mean taken to vary as one
  reading, for the share of a block it spans (`Track#level`): its
  readings are correlated with the block just closed, so a block of
  minutes adds little the CUSUM has not seen. Against two others or
  more, one reading alone whose z = y / √(variance + R) is beyond
  h + k counts whole: a large step is flagged before its block closes.
  Against a single other it does not: one other's reading cannot tell
  its own spike from the part's, and only the CUSUM counts. The CUSUM
  then restarts as the return test below.
- **back to ok**: while jumped, the track's delta and variance are
  held as they were at the jump, and each closed block goes to a
  return CUSUM, the jump's mirrored: `cusum_up` + k − z̄ and
  `cusum_down` + k + z̄, each held between 0 and h + k, z̄ read
  within ±(h/2 − k) of zero (±2 with the defaults) before it enters
  either side. That clip is k at least, so `cusum_h` is at least 4
  `cusum_k`; a `Quantity` below is refused. A side climbs only while
  the error is back on its side of the delta held, and the time the
  error spent away counts for no more than one block of being back;
  one block
  moves a side by h/2 at most, so no two blocks fill one, however far
  they swing: a return is told by time, not by magnitude. Both above
  h, the error is within k of it, with the evidence a jump takes, and
  the track is ok again, its CUSUM restarted. A part back at its
  delta, its block means scattered around it, climbs by k a block on
  average and clears in about eleven blocks (33 h). Otherwise it stays
  jumped until its offset is relearned or `Tracker#reset` drops it.
- **drifting**: |delta| above `drift_alarm` × the offset's σ; back to
  ok under `drift_clear` × σ. Not for a reference.

An Offset's σ, here as in the drift alarm and a reference's width, is
the one its corrections carry: its spread / 2.563 / |1 + gain +
coefficient|, where delta and the innovations are (`Offset#correct`).
A sensor with a neighbour of k = +0.6 drifts at 3 of that σ, not at 3
of its gap's.

```text
the CUSUM's higher side after each closed block, then with the
block under way counted for the share of a block it spans
(illustrative)

block 1        ██████······················│
block 2        █████████████···············│
block 3        ████████████████████········│
under way 1 h  ████████████████████████····│    a third of it
under way 3 h  ███████████████████████████████  above h: jumped
                                           h (cusum_h)

a reading      |z| above h + k                  jumped at once
               (against two others or more)
```

```text
the return CUSUM of a jumped track, at each closed block, z its
mean innovation standardised against the delta held (illustrative)

  z read within ±(h/2 - k), ±2: a block beyond counts as ±2
  up = up + k - z,  down = down + k + z,  each held in 0 .. h + k

the error still away, z = +2 at each block:
  block       1     2     3     4     5   ...
  up          0     0     0     0     0   never climbs: jumped
  down      2.5   5.0   5.5   5.5   5.5   held at h + k

the error back at the delta held, z = 0 at each block:
  block       1     2     3   ...    10    11
  up        0.5   1.0   1.5   ...   5.0   5.5
  down      0.5   1.0   1.5   ...   5.0   5.5   both above h: ok
```

| `Quantity` setting | default                                |
| ------------------ | -------------------------------------- |
| `track_q`          | (σ/2)² in half a day: σ² / 48 per hour |
| `cusum_block`      | 10 800 s (3 h)                         |
| `cusum_k` (k)      | 0.5                                    |
| `cusum_h` (h)      | 5, at least 4 `cusum_k`                |
| `drift_alarm`      | 3                                      |
| `drift_clear`      | 2                                      |

In the fusion, a tracked part's corrected value has its delta taken
out and its σ² the track's variance added, but for a reference's
pinned track, which adds nothing: the reference's σ stays the
location's (set, or measured by its collocation and bounded, else
the quantity's; see Fusing). A jumped part does not count (`jumped`),
a drifting one counts (`drifting`). A jumped reference
does not count either; the other sensors' corrections stay as they
are, their offsets telling what the reference reads when healthy. A
track is applied only while its fingerprint is the moment's.

```ruby
offsets = store.offsets("temperature")
shifts  = store.shifts("temperature")
tracker = Sensorium::Tracker.new(setup, offsets:)
tracks  = store.tracks("temperature")

fused  = Sensorium::Fusion.new(setup, offsets:, shifts:, tracks:)
                          .location("green-room", snapshot)
fused.value                                     # with the tracks
tracks = tracker.update(tracks, fused)          # new tracks, pure
store.keep_tracks("temperature", tracks)        # replaces those given
```

A `Tick` does all of it for every location at once: see Running it.

`Tracker#update` takes a `Fused` made with tracks or without: each
`Weighted` part carries, as `untracked`, the `Part` before its track
was applied (the part itself when it has none), and the Tracker takes
that, so each delta is taken out once, by the Tracker, and a drifting
part still counts and can clear. Made with tracks or without, the
`Fused` gives the same tracks. `tracker.reset(tracks, "green-room",
"tado")` drops a track, which starts afresh at its next update.

Given transient profiles (`transients:`, see Transients) and the
snapshot the `Fused` was made from, the Tracker leaves every part of a
location as it was while the `Detector` finds an event there at the
moment, as it leaves a part with too few others: an opened window
would read as a step and could push a CUSUM to a `jumped` that holds
for a day and more, until the return CUSUM clears it. Without
profiles or snapshot, it tracks as before.

```ruby
tracker = Sensorium::Tracker.new(
    setup, offsets:,
    locations: store.locations("temperature"),
    transients: store.transients("temperature")
)
tracks  = tracker.update(tracks, fused, snapshot:)
```

The gain is small by design. In the tests' room (a sensor of
σ 0.2 °C against two of 0.1 and 0.08), ten hourly updates take delta
to 21 % of a constant bias, 48 hourly ones to 75 % and ten daily ones
to 87 %, while a step of 3 σ is flagged jumped at the tenth hourly
update, and the reference stepping by 5 σ at the seventh. In a real
room recorded over a winter (its last ten days, tracked against what
its first twenty learned), no part is flagged, where taking each
reading alone flagged a wall sensor within eleven hours; steps of 1, 2
and 3 of its offset's σ put into its readings are flagged after 37,
10 and 5 hours at ten-minute updates, and the same hourly.

## Running it

What a store keeps of a quantity is one `Knowledge`
(`store.knowledge("temperature")`: offsets, shifts, locations, tracks,
dynamics, transient profiles, collocations); the `Fusion`, the
`Tracker` and the `Transient::Detector` each take it as `knowledge:`,
none of them the dynamics, which are the caller's (see Dynamics). A
`Tick` runs the ten-minute cycle on it:

```ruby
setup = Sensorium::Presets.room
loop do                                         # every ten minutes
    snapshot = Sensorium::Snapshot.from(source, setup, at: Time.now)
    tick = Sensorium::Tick.new(setup, store.knowledge("temperature"))
                          .call(snapshot)
    tick.fused        # { location => Fused }, made with the tracks
    tick.events       # [Transient::Event] of the moment
    store.keep_tracks("temperature", tick.tracks)
    sleep 600
end
```

Each location is fused once, with the tracks the `Knowledge` holds;
the `Tracker` is updated from those `Fused` (each part as it was
before its track, see Tracking), with the snapshot for the
`Detector`; and the `Detector` gives the events.
The tracks updated show in the next tick's `Fused`, not in this one's.

A blend, if wanted, takes the `Fused` as they come:

```ruby
Sensorium::Blend.new({ "downstairs" => 0.8, "green-room" => 0.2 })
                .of(tick.fused).value
```

A `Tick` holds nothing between calls: the tracks it gives back are all
those it was given, updated, and `keep_tracks` keeps them for the next
`store.knowledge`. For a
quantity with a transform, `call(snapshot, context:)` takes each
location's context ({ location => context }, or anything answering
`call(location)`): humidity is brought back at the location's
temperature, the temperature tick's value; without one, a `Fused` has
its `inside` but no `value` or `sigma` as the quantity reads.

## Any quantity

```ruby
Sensorium::Quantity.new(name: "co2", unit: "ppm", sigma: 30, drift: 200)
```

A `Transform` takes a quantity where a sensor's error adds up, and back.
Relative humidity is learned and fused as absolute humidity
(`Transform::AbsoluteHumidity`): a sensor 1 °C warmer than the room
reads about 6 % lower for the same air. Each humidity reading needs its
sensor's temperature (`Reading#context[:temperature]`); one without
it, or without a value, is left out (the transform answers nil), and
the fused
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

- `sensors(quantity)`: `[Sensor]`, its name, location, tags and
  whether it may be a neighbour.
- `readings(quantity, from, to, devices)`: `[Reading]`, its time,
  location, device, value and context; `devices` nil for all.
- `externals(quantity, from, to)`, optional: `[Reading]` with location
  nil.
- `events(influence, from, to)`, optional: `[[time, location, value]]`.

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
`tables: { collocations: }`; `sensor_transients`,
`tables: { transients: }`), which a caller with its own schema creates
too, as `Store::Sequel::Schema` does. An offset's maps (switches,
taus, series, states) are kept as JSON, as are a location's `deltas`,
a dynamics model's `b`, a collocation's `sigmas` and a profile's
`own` and `relative` thresholds (`{ "600": [fall, rise] }`).

Tables made before the survey rounds lack six columns of
`sensor_offsets`: `taus`, `series` and `states` (text), `rate`,
`off_p10` and `off_p90` (float), and `sensor_locations` lacks `deltas`
(text); a caller with its own schema adds them. Tables made before the
blocks (0.2.0) lack `block_share` (float) in `sensor_offsets`, and
`block_sum`, `block_noise` (float), `block_count` (integer) and
`block_at` (time) in `sensor_tracks`: opened with `migrate: true`, a
store adds them; a caller with its own schema adds them itself. A
track kept before them starts its block afresh.

A caller whose tables name their columns its own way says so with
`columns:`, sensorium's name to its own, the same in every table
(`columns: { location: :zone, device: :sensor }`); a name that is no
column of the store's, or two columns given one name, is refused.
Another store answers the same fifteen methods (see
`lib/sensorium/store/memory.rb`), and `knowledge(quantity)` from them
by including `Store::Knowing`. A time `Store::Sequel` keeps
(`learned_from`, `learned_to`, `learned_at`, `tracked_at`, `block_at`)
is stored and read back as UTC, whether Sequel converts times (a
`database_timezone` set, as an application in local time with a UTC
session does) or not, but for the one case below: the columns may be
DATETIME or TIMESTAMP. With no
`database_timezone`, or `:utc`, a time is read as its text and parsed
as UTC, so one in the hour the clocks skip every spring round-trips.
With `database_timezone` `:local`, a time in the hour the clocks
repeat every autumn is stored as an ambiguous local wall clock and
may read back an hour off.

Every `keep_*` method follows the one rule: it replaces what shares
the kept rows' key, and leaves the rest. Keeping dynamics
(`keep_dynamics`) or collocations (`keep_collocations`) replaces those
of the same location and regime; transient profiles
(`keep_transients`), those of the same location, device and regime;
and tracks (`keep_tracks`), those of the same location and device.

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

- A tado's reading while its own valve works is below its idle one,
  the radiator warming its sensor less than the room's reference (by
  0.06 to 0.5 °C on one house's winter); no input carries the valve's
  own duty, so `predict` misses it, within its σ. A Switch of
  location scope on the zone's heating events, or a Series on the
  valve's power, would; untried. On the same winter, one tado's
  prediction while regulating was overconfident (var(z) 4.6, its
  spread twice its σ).

- Only an offset's level is followed online (Tracking); its terms
  change only when learning runs again.
- Until a sensor is the suspect, the others' deltas may take in a
  little of its step (0.006 °C of 0.6 in the tests' room).
- A step is flagged in hours, not at the next reading: a block must
  close, and the CUSUM add up over a few. One of a sensor's own σ takes
  about a day; meanwhile its delta takes some of it in, and a step
  slow enough to be taken in whole is never flagged, only seen as
  drifting.
- In a location of three with a jumped reference, the two sensors left
  without it stand still until a relearn, a reset or the jumped one
  clearing: their disagreement cannot be put on either.
- A sensor judged against its reference alone takes the reference's
  excursions as its own: one of hours can be put on the sensor (once on
  one house's year, 81 h). In a location of two, which part moved
  cannot be told.
- A jumped track is measured against the delta it held at the jump,
  which has taken in part of a step during the hours the CUSUM took to
  flag it: a sensor whose step was real, then undone, may come back
  short of that delta and not clear before a relearn.
- A reference's step smaller than about the location's tightest
  Offset σ is not flagged: it is within what the room usually sees of
  the reference. In a room whose third sensor is noisy, which of the
  two tight ones a step between them is put on is still decided by
  noise.
- The terms are kept by tests on the correction's spreads (80 % on the
  bins fitted, no wider, or within 5 %, on those held out) whose own
  noise, a sensor's error persisting for hours, is several times 5 %
  over a held-out tenth of a few days: the held-out test refuses only
  what it plainly denies.
  The widths a term is kept with are widened by what the bins held
  out confirm, which bounds what a term the test let through costs.
  On one house's year, the held-out narrowing of a term predicts the
  narrowing of the later bins in winter (rank correlation 0.6), barely
  in the mid season (0.3: its last tenth is late October, most of its
  bins April and May), not in summer.
- The room preset's humidity σ and drift are first guesses, not
  measured: triple collocation needs three humidity series in a
  location.
- The fused σ still assumes the parts' errors independent: an error
  they share (the reference's, the sun, a radiator's plume) is not in
  it, and neither triple collocation nor a leave-one-out on the same
  data can see one (DESIGN.md, Fusion). The collocations give a sole
  reference its σ, and nothing else.
- A sensor's σ is the spread of its difference to the reference, the
  reference's own noise counted in: with a noisy reference it errs
  wide (a left-out part's var(z) 0.76 in the tests' room, the
  reference's σ 0.1; the fused value's var(z) 0.41 against the truth
  in the tests' noisy room, its reference three times noisier and its
  σ learned): the safe side.
- A location without a reference is fused from its readings as they
  read: its σ says how fresh they are, not how far its sensors differ
  from one another.
- The per-state spreads cover the Switches, Thresholds and Series,
  not the Modes (a Shift has its own spread).
- A dynamics model's q is calibrated on the span it was fitted on:
  another season may move more, or less.
- The bins under a Mode, and its hold, are left out of learning: a
  house whose aircon cools most summer days learns little or no
  summer offset. How little has not been measured.
- A sensor under a Mode's value it has no Shift for yet (a value's
  first weeks in a regime) takes the plain offset alone: it is off by
  about the Shift learned later (up to 1.1 °C on one sensor of one
  house's year), its σ not saying so, until the value has held
  `min_shift` bins and the next learning runs.
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
- One house's downstairs Airzone spikes for 3 to 6 hours at a time,
  from a cause of its own; how to take them (a transient profile of
  their own) is open.

## Upgrading

From 0.1.x to 0.2.x, what a caller must change:

- `Tick#call` takes no `previous:`, nor `Tracker#update`: the witness
  that used it is gone; drop the argument and the state kept for it.
- A `Tracker` and a `Fusion` are made without `dynamics:`; Dynamics
  stays a toolkit of its own (`Dynamics.learn`), no longer used by the
  Fusion. A `Fusion` takes `collocations:` (optional: a sole
  reference's σ), which a `Knowledge` from a store carries already.
- A `Parts::Part` carries the reading's `time`; `Offset#correct` takes
  `held:`, whether a Mode holds.
- A store gains five columns: `block_share` on offsets; `block_sum`,
  `block_noise`, `block_count` and `block_at` on tracks. A Sequel
  store adds them itself, unless opened with `migrate: false`: then
  add them by hand first.
- Since 0.2.3, a `Quantity` with `cusum_h` below 4 `cusum_k` raises
  ArgumentError (Tracking).

And what changes without a call changing: a Switch's text values
("off" and "false" are off, Learning), the Shift of two Modes holding
at once (`aircon+fan`), a Mode with no Shift for its value (the plain
offset), and regimes asked of local times.

## Gate

`bundle exec rake`: the tests, then RuboCop.
`test/recorded_room_test.rb` runs on a real room's recording, thirty
winter days kept out of the repository (`local/fixture/room.json.gz`):
without it, its tests are skipped.
