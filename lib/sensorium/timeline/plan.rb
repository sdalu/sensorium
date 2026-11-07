# frozen_string_literal: true

module Sensorium
    class Timeline
        # What a Timeline is made of besides its source and span, for a
        # caller with no Setup: the influences and the bin's width in
        # seconds. A Setup answers the same (influences by kind, series).
        Plan = Data.define(:influences, :bin) do
            include Influence::Kinds

            def series = Series.new(bin)
        end

        # The Timeline of the influences over from..to, from the
        # source's events (source.events(name, from, to)), in bins of
        # `bin` seconds.
        def self.of(influences, source, from:, to:, bin:)
            new(Plan.new(influences:, bin:), source, from, to)
        end
    end
end
