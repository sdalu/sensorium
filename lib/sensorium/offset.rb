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
    # neighbour, a Series' value or dr/dt is not known.
    Offset = Data.define(:location, :device, :quantity, :regime, :reference,
                         :constant, :switches, :taus, :series, :gain,
                         :neighbour,
                         :coefficient, :rate, :p10, :p90, :samples, :plain,
                         :plain_p10, :plain_p90) do
        def initialize(taus: {}, series: {}, rate: nil, **) = super

        # The reference's value, as this sensor's reading tells it: the
        # model solved for r. shifts: the Shifts of the Modes holding;
        # moment: what else holds (Offset::Moment). While a Mode holds,
        # or when the neighbour, a Series' value or dr/dt is not known,
        # the plain offset: a Shift was learned over it.
        def correct(reading, shifts: [], **moment)
            now = Offset::Moment.new(**moment)
            if shifts.any? || unknown?(now)
                return plain_correct(reading, shifts)
            end
            model_correct(reading - constant - known(now), now.neighbour.to_f)
        end

        def sigma       = (p90 - p10) / P10_P90
        def plain_sigma = (plain_p90 - plain_p10) / P10_P90

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

        # What r is multiplied by, the model solved.
        def scale = 1 + (gain || 0.0) + k

        # gap: the reading less the terms that do not involve r.
        def model_correct(gap, neighbour)
            Estimate.new(value: (gap + (k * neighbour)) / scale,
                         sigma: sigma / scale.abs)
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
