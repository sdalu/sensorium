# frozen_string_literal: true

module Sensorium
    # How a sensor reads against its location's reference r, in a regime:
    #   sensor - r = constant
    #              + Σ switches[name] × (that Switch on)
    #              + gain × r
    #              + coefficient × (r - neighbour)
    # a term nil (or absent from switches) when it did not narrow the
    # spread; p10..p90 is what the model leaves. plain is the constant
    # alone and plain_p10..plain_p90 its spread, the fallback when the
    # neighbour is not known.
    Offset = Data.define(:location, :device, :quantity, :regime, :reference,
                         :constant, :switches, :gain, :neighbour,
                         :coefficient, :p10, :p90, :samples, :plain,
                         :plain_p10, :plain_p90) do
        # The reference's value, as this sensor's reading tells it: the
        # model solved for r. on: the names of the Switches on;
        # neighbour: its value, when the model has one; shifts: the
        # Shifts of the Modes holding.
        def correct(reading, on: [], neighbour: nil, shifts: [])
            if self.neighbour && neighbour.nil?
                return plain_correct(reading, shifts)
            end
            model_correct(reading - constant - switched(on) - moved(shifts),
                          neighbour.to_f, shifts)
        end

        def sigma       = (p90 - p10) / P10_P90
        def plain_sigma = (plain_p90 - plain_p10) / P10_P90

        private

        def k = coefficient || 0.0

        # What r is multiplied by, the model solved.
        def scale = 1 + (gain || 0.0) + k

        # gap: the reading less the terms that do not involve r.
        def model_correct(gap, neighbour, shifts)
            Estimate.new(value: (gap + (k * neighbour)) / scale,
                         sigma: widest(sigma, shifts) / scale.abs)
        end

        def plain_correct(reading, shifts)
            Estimate.new(value: reading - plain - moved(shifts),
                         sigma: widest(plain_sigma, shifts))
        end

        def switched(on)
            (switches || {}).sum { |name, term| on.include?(name) ? term : 0 }
        end

        def moved(shifts) = shifts.sum(&:shift)

        def widest(sigma, shifts) = [sigma, *shifts.map(&:sigma)].max
    end
end
