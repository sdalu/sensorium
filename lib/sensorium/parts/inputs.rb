# frozen_string_literal: true

module Sensorium
    class Parts
        # What a location's models need at the moment besides each
        # sensor's reading, from the snapshot: the Switches and
        # Thresholds on, the filtered Switches' exposures, the Series'
        # values, the reference's rate.
        class Inputs
            # location: a resolved Location; references: [device], nil
            # when it has none.
            def initialize(location, references, snapshot, setup)
                @location   = location
                @references = references || []
                @snapshot   = snapshot
                @quantity   = setup.quantity
                @series     = setup.series
                @setup      = setup
            end

            # The names of the Switches and of the Thresholds on.
            def on = @snapshot.on(@location.name) + thresholds

            # An offset's exposures, values and dr_dt (Offset::Moment).
            def of(offset)
                { exposures: exposures(offset.taus), values:, dr_dt: }
            end

            # { name => exposure } of the filtered Switches, taus: { name
            # => tau } as the offset learned them: the filter run over
            # the 5 tau before the moment.
            def exposures(taus)
                taus.to_h do |name, tau|
                    at = @snapshot.at
                    [name, @series.filtered(pulsed(name), at - (5 * tau), at,
                                            tau)
                                  .fetch(@series.bin(at))]
                end
            end

            # { name => value } of the Series where the location is.
            def values = @snapshot.fed(@location.name)

            # The reference's rate, per hour: the mean of each
            # reference's, from its two latest readings within max_age;
            # nil when one has fewer.
            def dr_dt
                return @dr_dt if defined?(@dr_dt)
                rates = @references.map { rate(it) }
                @dr_dt = (rates.sum / rates.size unless rates.include?(nil))
            end

            private

            def pulsed(name)
                by = @snapshot.pulses.fetch(name, {})
                by.fetch(nil, Set.new) | by.fetch(@location.name, Set.new)
            end

            # The Thresholds on: the reference, as it reads, above within
            # their hold.
            def thresholds
                return [] if @setup.thresholds.empty? || @references.empty?
                now = @series.bin(@snapshot.at)
                raw = raw_reference
                @setup.thresholds.filter_map do |threshold|
                    threshold.name if threshold.on(raw, @series).include?(now)
                end
            end

            def raw_reference
                @series.reference(@references.map do |device|
                    @series.means(@snapshot.history
                                           .fetch([@location.name, device], []))
                end, @setup.carry)
            end

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
