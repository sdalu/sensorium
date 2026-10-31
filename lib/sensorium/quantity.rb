# frozen_string_literal: true

module Sensorium
    # What is measured, and the defaults a Location takes for it, in the
    # transform's units (the space it is learned and fused in):
    #   sigma     a sole reference's own error (one σ)
    #   drift     how fast the value may move, per hour: an old reading
    #             is trusted less by drift × its age
    #   max_age   minutes after which a reading is not used
    #   outlier   how many σ off the others a sensor is dropped
    #   transform Transform::Identity, Transform::AbsoluteHumidity…
    Quantity = Data.define(:name, :unit, :sigma, :drift, :max_age,
                           :outlier, :transform) do
        def initialize(unit: nil, max_age: 60, outlier: 3,
                       transform: Transform::Identity, **)
            super
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
