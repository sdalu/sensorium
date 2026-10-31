# frozen_string_literal: true

module Sensorium
    # What is measured, and the defaults a Location takes for it, in the
    # transform's units (the space it is learned and fused in):
    #   sigma     a sole reference's own error (one σ)
    #   drift     how fast the value may move, per hour: an old reading
    #             is trusted less by drift × its age
    #   max_age   minutes after which a reading is not used
    #   outlier   how many σ off the others a sensor is dropped
    #   floor     the least σ a reading is given, however tight its
    #             offset was learned (a quarter of sigma unless set)
    #   transform Transform::Identity, Transform::AbsoluteHumidity…
    Quantity = Data.define(:name, :unit, :sigma, :drift, :max_age,
                           :outlier, :floor, :transform)

    class Quantity
        DEFAULTS = { unit: nil, max_age: 60, outlier: 3, floor: nil,
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
