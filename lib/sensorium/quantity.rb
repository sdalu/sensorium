# frozen_string_literal: true

module Sensorium
    # What is measured, and the defaults a Location takes for it, in the
    # transform's units (the space it is learned and fused in):
    #   sigma     a sole reference's own error (one σ)
    #   drift     how fast the value may move, per hour: an old reading
    #             is trusted less by drift × its age
    #   max_age   minutes after which a reading is not used
    #   robust_nu the Student-t ν the Fusion reweights parts by: lower
    #             downweights a disagreeing part harder (4)
    #   outlier_factor a part's reweighted share of 1/σ² below which it
    #             is noted "outlier" (0.2)
    #   floor     the least σ a reading is given, however tight its
    #             offset was learned (a quarter of sigma unless set)
    #   transform Transform::Identity, Transform::AbsoluteHumidity…
    Quantity = Data.define(:name, :unit, :sigma, :drift, :max_age,
                           :robust_nu, :outlier_factor, :floor, :transform)

    class Quantity
        DEFAULTS = { unit: nil, max_age: 60, robust_nu: 4.0,
                     outlier_factor: 0.2, floor: nil,
                     transform: Transform::Identity }.freeze

        def initialize(name:, sigma:, **settings)
            given = DEFAULTS.merge(settings)
            super(**given, name: name.to_s, sigma:,
                           floor: given[:floor] || (sigma / 4.0))
        end

        # The readings taken into the transform's space, those it cannot
        # take left out.
        def inward(readings)
            readings.filter_map do |reading|
                value = transform.forward(reading.value, reading.context)
                reading.with(value:) if value
            end
        end
    end
end
