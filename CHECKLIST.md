# Closing a round on sensorium

## Gates

- [ ] `bundle exec rake` passes: tests, then RuboCop.
- [ ] If the learner or the fit changed: `Presets.room` still learns
  what it learned on real history (DESIGN.md, "It learns what
  ClimatControl learned"): same offsets and neighbours, constants
  within 0.01.

## Documents

- [ ] `README.md`: do the examples still run, and are the known
  shortfalls still the true ones?
- [ ] `DESIGN.md`: did this round change a reason it gives, or make a
  choice it should record?

## Release

- [ ] Does `Sensorium::VERSION` in `lib/sensorium/version.rb` move with
  this round? It is the one place the release number is written. Its
  users (MadHouse, ClimatControl) pin a tag.
