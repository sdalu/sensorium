# Closing a round on sensorium

## Gates

- [ ] `bundle exec rake` passes: tests, then RuboCop.
- [ ] If the learner or the fit changed, does the real-history
  comparison (CLAUDE.local.md) show only differences the commit
  message explains? The run needs a house's database, so it is not
  part of the suite.

## Documents

- [ ] `README.md`: do the examples still run, and are the known
  shortfalls still the true ones?
- [ ] `DESIGN.md`: did this round change a reason it gives, or make a
  choice it should record?

## Release

- [ ] Does `Sensorium::VERSION` in `lib/sensorium/version.rb` move with
  this round? It is the one place the release number is written. Its
  users (MadHouse, ClimatControl) pin a tag.
- [ ] Is the real-data fixture still to stay out of the public suite?
  It lives in the gitignored `local/` (30 days of one room, raw
  readings, device names anonymised), and its tests skip without it.
  Publishing it shows a household's routines (heating, aircon, windows,
  presence); ask the owner at each release before moving it to `test/`.
