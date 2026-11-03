# frozen_string_literal: true

module Sensorium
    class Parts
        # How much a reading's estimate of the reference has aged, in
        # the transform's space: its value stays and its σ grows by
        # drift × age. For a device with a delta (send-on-delta), what
        # the age adds to σ² is at most delta² / 3, the delta taken into
        # the transform's space at the reading. σ is never below the
        # quantity's floor.
        class Aging
            # location: a resolved Location.
            def initialize(location, snapshot, setup)
                @location = location
                @snapshot = snapshot
                @setup    = setup
            end

            # The Estimate a reading gave, aged; one with σ nil (not
            # corrected) as it is. Its value, unmoved, is a Float
            # (+ 0.0), a whole-number reading's included.
            def of(device, reading, estimate)
                return estimate unless estimate.sigma
                spread = (@location.drift * hours(reading))**2
                spread = capped(spread, device, reading)
                Estimate.new(value: estimate.value + 0.0,
                             sigma: Math.sqrt((floored(estimate)**2) +
                                              spread))
            end

            private

            # The reading's age, hours; one stamped after the moment (a
            # replayed snapshot) is fresh, not of a negative age.
            def hours(reading) = [@snapshot.age(reading), 0].max / 3600.0

            # The age's variance, at most delta² / 3 for a device with a
            # delta.
            def capped(spread, device, reading)
                delta = @location.deltas[device] or return spread
                inside = inside(reading, delta) or return spread
                [spread, (inside**2) / 3.0].min
            end

            # The delta as the transform takes it at the reading.
            def inside(reading, delta)
                ends = [reading.value, reading.value + delta].map do |value|
                    quantity.transform.forward(value, reading.context)
                end
                (ends.last - ends.first).abs unless ends.include?(nil)
            end

            def floored(estimate) = [estimate.sigma, quantity.floor].max

            def quantity = @setup.quantity
        end
    end
end
