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

        # The changes over a window beyond which a sensor is in a
        # transient: a fall at or below `fall`, a rise at or above
        # `rise`.
        Threshold = Data.define(:fall, :rise) do
            # [direction, z] of a change beyond, z the change over its
            # threshold (1 or more); nil within.
            def beyond(change)
                return [:fall, change / fall] if change <= fall
                [:rise, change / rise] if change >= rise
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
        # past the smallest change that is not 0. Nil when fewer than
        # min_samples, or none is not 0.
        def threshold(changes, setup)
            return if changes.size < setup.min_samples
            step = changes.map(&:abs).reject(&:zero?).min or return
            share = setup.transient_rate * setup.bin / 86_400.0
            Threshold.new(fall: raised(Stats.quantile(changes, share), -step),
                          rise: raised(Stats.quantile(changes, 1 - share),
                                       step))
        end

        def raised(value, step) = value.zero? ? step * RAISE : value
    end
end

require_relative "transient/changes"
require_relative "transient/detector"
