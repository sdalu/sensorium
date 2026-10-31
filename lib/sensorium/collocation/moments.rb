# frozen_string_literal: true

module Sensorium
    class Collocation
        # What held at a location's bin, as an Offset::Moment's
        # arguments: the Switches and Thresholds on (their hard hold),
        # a filtered Switch's exposure, the neighbour's value, the
        # Series' values, the reference's rate.
        class Moments
            # given: reference:, rates:, { bin => value } of the
            # reference's carried series and its rate; switched:
            # { name => bins on }; gaps: { neighbour => { bin =>
            # reference - neighbour } }.
            def initialize(location, timeline, **given)
                @reference, @rates, @switched, @gaps =
                    given.values_at(:reference, :rates, :switched, :gaps)
                @exposures = timeline.exposures(location)
                @series    = timeline.series(location)
            end

            def at(offset, bin)
                { on: @switched.filter_map do |name, bins|
                    name if bins.include?(bin)
                end,
                  exposures: offset.taus.to_h do |name, tau|
                      [name, @exposures.dig(name, tau, bin) || 0.0]
                  end,
                  neighbour: neighbour(offset.neighbour, bin),
                  values: values(bin), dr_dt: @rates[bin] }
            end

            private

            def neighbour(name, bin)
                gap = name && @gaps.dig(name, bin) or return
                @reference[bin] - gap
            end

            def values(bin)
                @series.filter_map do |name, by|
                    [name, by[bin]] if by[bin]
                end.to_h
            end
        end
    end
end
