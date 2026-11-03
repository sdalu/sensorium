# frozen_string_literal: true

module Sensorium
    # Sudden changes no learned term explains (a window opened, a
    # shower, the sun on a sensor), told apart by how far a sensor's
    # change over a window goes beyond the changes it usually makes.
    # Each sensor's thresholds are learned (learn), per regime and
    # window;
    # the Detector finds the events of a Snapshot by them; a Learner
    # given an Influence::Transient leaves the bins they cover out of
    # the offsets.
    module Transient
        # How far past the sensor's smallest step a threshold raised from
        # 0 is set, so that a single step, read with a float's noise, is
        # no event.
        RAISE = 1 + 1e-6

        # The decimals a change is compared at: one step reads as floats
        # a few ulps apart (1e-15 at 20, 1e-11 at 1e5), equal readings
        # binned apart as a change of 1e-15; no sensor reads 1e-9.
        DIGITS = 9

        # The changes over a window beyond which a sensor is in a
        # transient: a fall at or below `fall`, a rise at or above
        # `rise`.
        Threshold = Data.define(:fall, :rise) do
            # [direction, z] of a change beyond, z the change over its
            # threshold (1 or more); nil within.
            def beyond(change)
                at = Transient.canonical(change)
                return [:fall, change / fall] if at <= Transient.canonical(fall)
                [:rise, change / rise] if at >= Transient.canonical(rise)
            end
        end

        # A sensor's thresholds in one regime, { window => Threshold }:
        # own, of its own change; relative, of the change of its gap to
        # its location's reference (none for a reference itself).
        Profile = Data.define(:location, :device, :quantity, :regime, :own,
                              :relative)

        # A change seen at `at`: direction :fall or :rise, z the change
        # over `window` seconds over the sensor's own threshold (1 or
        # more).
        Event = Data.define(:location, :device, :direction, :z, :window,
                            :at)

        module_function

        # [Profile] of every sensor of the source over a span, from a
        # source as the Learner's; span: from:, to: and locations:
        # ({ name => Location }, those set, for the references), the
        # History loaded from the source when none is given.
        def learn(source, setup, history: nil, **span)
            history = Sensorium::History.given(history, source, setup, span)
            Changes.new(history).profiles
        end

        # The devices read: the sensors, and the references set.
        def names(sensors, locations)
            (sensors.map(&:name) +
             locations.values.flat_map(&:references)).uniq
        end

        # The Threshold of changes: their quantiles at the share of the
        # bins transient_rate allows, each side, one of 0 raised just
        # past the smallest change that is not 0, one several changes
        # sit at (ties) raised just past itself when leaving them out
        # comes nearer the share. Nil when fewer than min_samples, or
        # none is not 0.
        def threshold(changes, setup)
            return if changes.size < setup.min_samples
            step = changes.map(&:abs).reject { canonical(it).zero? }.min or
                return
            share = setup.transient_rate * setup.bin / 86_400.0
            Threshold.new(fall: side(changes, share, -step),
                          rise: side(changes, 1 - share, step))
        end

        # The quantile at fraction, on the side of step's sign, raised.
        def side(changes, fraction, step)
            value = Stats.quantile(changes, fraction)
            return raised(value, step) if canonical(value).zero?
            tied?(changes, fraction, value, step) ? past(value) : value
        end

        # Whether several changes sit at value, and leaving them out of
        # those beyond comes nearer the share than counting them.
        def tied?(changes, fraction, value, step)
            sides = sides(changes, value, step)
            at = sides.count { it >= 0 }
            past = sides.count(&:positive?)
            allowed = [fraction, 1 - fraction].min * changes.size
            at - past > 1 && (past - allowed).abs < (at - allowed).abs
        end

        # Each change's side of value, as compared: 1 past it on step's
        # side, 0 at it, -1 short of it.
        def sides(changes, value, step)
            sign = step <=> 0
            changes.map { sign * (canonical(it) <=> canonical(value)) }
        end

        def raised(value, step)
            canonical(value).zero? ? past(step) : value
        end

        # The value moved away from 0 by RAISE, by two units of the grid
        # changes are compared at at least (a raise survives the
        # rounding, whatever the step).
        def past(value)
            by = [value.abs * (RAISE - 1), 2 * (10.0**-DIGITS)].max
            value + ((value <=> 0) * by)
        end

        # A change as it is compared, a float's noise rounded off.
        def canonical(change) = change.round(DIGITS)
    end
end

require_relative "transient/changes"
require_relative "transient/detector"
