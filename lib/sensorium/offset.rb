# frozen_string_literal: true

module Sensorium
    # How a sensor reads against its location's reference r, in a regime:
    #   sensor - r = constant
    #              + Σ switches[name] × (that Switch on, or its exposure
    #                                    when filtered: taus[name])
    #              + Σ series[name] × (that Series' value)
    #              + gain × r
    #              + coefficient × (r - neighbour)
    #              + rate × dr/dt (per hour)
    # a term nil (or absent from switches) when it did not narrow the
    # spread; p10..p90 is what the model leaves. plain is the constant
    # alone and plain_p10..plain_p90 its spread, the fallback when the
    # neighbour, a Series' value or dr/dt is not known. states:
    # { name => [p10, p90] } of what the model leaves over the bins each
    # Switch (or Threshold) kept as a term was on, and off_p10..off_p90
    # over the bins all of them were off; { "NAME:high" => [p10, p90,
    # median], "NAME:low" => [p10, p90, median] } over the bins each
    # Series kept as a term was above its median over the fit, and
    # not; each absent when too few bins had it. block_share: the spread
    # of what the model leaves, averaged over blocks of the quantity's
    # cusum_block, as a share of its spread bin by bin (1/√n if the bins
    # were independent, near 1 for a sensor whose error persists for
    # hours); nil when too few blocks were seen. The Tracker's CUSUM
    # takes a block's mean innovation in it.
    Offset = Data.define(:location, :device, :quantity, :regime, :reference,
                         :constant, :switches, :taus, :series, :gain,
                         :neighbour,
                         :coefficient, :rate, :p10, :p90, :samples, :plain,
                         :plain_p10, :plain_p90, :states, :off_p10,
                         :off_p90, :block_share) do
        def initialize(**given)
            given = Offset::OPTIONAL.merge(given)
            super(**given, states: (given[:states] || {})
                                   .transform_keys(&:to_s))
        end

        # The reference's value, as this sensor's reading tells it: the
        # model solved for r. shifts: the Shift of what the Modes hold,
        # when one was learned; held: whether a Mode holds at all;
        # moment: what else holds (Offset::Moment). While a Mode holds,
        # or when the neighbour, a Series' value or dr/dt is not known,
        # the plain offset: a Shift was learned over it, and one not
        # learned is not known, as any term's input may not be.
        def correct(reading, shifts: [], held: shifts.any?, **moment)
            now = Offset::Moment.new(**moment)
            return plain_correct(reading, shifts) if held || unknown?(now)
            model_correct(reading - constant - known(now), now.neighbour.to_f,
                          now)
        end

        def sigma       = (p90 - p10) / P10_P90
        def plain_sigma = (plain_p90 - plain_p10) / P10_P90

        # What r is multiplied by, the model solved: a correction, and
        # its width, is the gap's over it.
        def scale = 1 + (gain || 0.0) + k

        private

        def k = coefficient || 0.0

        def unknown?(now)
            (neighbour && now.neighbour.nil?) || (rate && now.dr_dt.nil?) ||
                series.keys.any? { now.values[it].nil? }
        end

        # The terms that do not involve r.
        def known(now)
            switched(now) + fed(now.values) + (rate ? rate * now.dr_dt : 0)
        end

        def fed(values) = series.sum { |name, term| term * values[name] }

        # gap: the reading less the terms that do not involve r.
        def model_correct(gap, neighbour, now)
            Estimate.new(value: (gap + (k * neighbour)) / scale,
                         sigma: width(now) / P10_P90 / scale.abs)
        end

        # The spread of what holds: the widest of the Switches on now
        # that were kept as terms, each its own when kept, else p10..p90,
        # or none on, the spread while all were off, when kept; and of
        # each Series' spread at its level now, when kept. Without any
        # of them, p10..p90.
        def width(now)
            [*switch_width(now), *level_widths(now.values)].max || (p90 - p10)
        end

        def switch_width(now)
            on = now.on.map(&:to_s) & (switches || {}).keys.map(&:to_s)
            return on.map { state_width(it) }.max if on.any?
            off_width
        end

        # The spreads of the Series at their level now: above the median
        # over the fit, "NAME:high", else "NAME:low"; those kept.
        def level_widths(values)
            series.filter_map { |name, _| level_width(name, values[name]) }
        end

        def level_width(name, value)
            median = (states["#{name}:high"] ||
                      states["#{name}:low"])&.last or return
            found = states["#{name}:#{value > median ? "high" : "low"}"]
            found && (found[1] - found[0])
        end

        def off_width = off_p10 && off_p90 && (off_p90 - off_p10)

        def state_width(name)
            low, high = states[name]
            low && high ? high - low : p90 - p10
        end

        def plain_correct(reading, shifts)
            Estimate.new(value: reading - plain - moved(shifts),
                         sigma: widest(plain_sigma, shifts))
        end

        # A filtered Switch's term × its exposure (none: 0), another's
        # while it is on.
        def switched(now)
            on = now.on.map(&:to_s)
            (switches || {}).sum do |name, term|
                next term * now.exposures.fetch(name, 0.0) if taus.key?(name)
                on.include?(name.to_s) ? term : 0
            end
        end

        def moved(shifts) = shifts.sum(&:shift)

        def widest(sigma, shifts) = [sigma, *shifts.map(&:sigma)].max
    end

    class Offset
        # The members an Offset may be made without.
        OPTIONAL = { taus: {}, series: {}, rate: nil, states: {},
                     off_p10: nil, off_p90: nil, block_share: nil }.freeze

        # What holds at the moment of a reading, besides the Modes: on,
        # the names of the Switches on; exposures, { name => exposure } of
        # the filtered ones; neighbour, its value; values,
        # { name => value } of the Series; dr_dt, the reference's rate
        # per hour. A value nil, or absent, is not known.
        Moment = Data.define(:on, :exposures, :neighbour, :values,
                             :dr_dt) do
            def initialize(on: [], exposures: {}, neighbour: nil,
                           values: {}, dr_dt: nil)
                super
            end
        end
    end
end
