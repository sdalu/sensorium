# frozen_string_literal: true

module Sensorium
    class Parts
        # What a location's models need at the moment besides each
        # sensor's reading, from the snapshot: the reference's rate.
        class Inputs
            # location: a resolved Location; references: [device], nil
            # when it has none.
            def initialize(location, references, snapshot, setup)
                @location   = location
                @references = references || []
                @snapshot   = snapshot
                @quantity   = setup.quantity
            end

            # The reference's rate, per hour: the mean of each
            # reference's, from its two latest readings within max_age;
            # nil when one has fewer.
            def dr_dt
                return @dr_dt if defined?(@dr_dt)
                rates = @references.map { rate(it) }
                @dr_dt = (rates.sum / rates.size unless rates.include?(nil))
            end

            private

            def rate(device)
                before, last = recent(device).last(2)
                return unless last && last.time > before.time
                values = [before, last].map { inward(it) }
                return if values.include?(nil)
                (values.last - values.first) * 3600.0 /
                    (last.time - before.time)
            end

            def recent(device)
                @snapshot.history.fetch([@location.name, device], [])
                         .select do |reading|
                             @snapshot.age(reading) <= @location.max_age * 60
                         end
            end

            def inward(reading)
                @quantity.transform.forward(reading.value, reading.context)
            end
        end
    end
end
