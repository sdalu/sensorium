# sensorium

How it works: README.md. Why it is shaped so: DESIGN.md. What closes a
round: CHECKLIST.md. What is open: EXPLORE.md.

Gate: `bundle exec rake`

Ruby style: the `ruby` skill (4-space indentation, double quotes,
`.rubocop.yml` is its rule set).

## Traps

- `a, b = call or return` is a syntax error; assign to one name first.
- A constant defined inside a Data.define block lands in the
  enclosing module, not the class: reopen the class for constants.
- `Data#with` is a method: no member may be named `with` (hence
  `Reading#context`).
- Inside `Sensorium::Store`, `Sequel` is the store class; the gem is
  `::Sequel`.
