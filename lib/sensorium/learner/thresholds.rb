# frozen_string_literal: true

module Sensorium
    class Learner
        # When each Threshold was on at a location: from its reference as
        # it reads, before the transform (the readings' raw values).
        class Thresholds
            # readings: [Reading], as the source told them.
            def initialize(setup, readings)
                @setup = setup
                @series = setup.series
                @raw = setup.thresholds.empty? ? {} : @series.of(readings)
            end

            # { name => Set of bins } at a location, of references
            # [device]; once per location.
            def of(location, references)
                return {} if @setup.thresholds.empty?
                (@of ||= {})[location] ||= begin
                    raw = reference(location, references)
                    @setup.thresholds.to_h do |threshold|
                        [threshold.name, threshold.on(raw, @series)]
                    end
                end
            end

            private

            def reference(location, references)
                @series.reference(references.map do |device|
                    @raw.fetch([location, device], {})
                end, @setup.carry)
            end
        end
    end
end
