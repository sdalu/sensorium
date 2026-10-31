# frozen_string_literal: true

require "support/fusion_helpers"

# FusionHelpers' room (temperature, 20 °C at AT), followed by a Filter.
module FilterHelpers
    include FusionHelpers

    HOUR = 3600

    private

    def filter(dynamics: [], locations: {})
        Sensorium::Filter.new(Sensorium::Presets.room.with(outside: "outside"),
                              dynamics:, locations:)
    end

    def calm
        filter(locations: { "room" => Sensorium::Location.new(name: "room",
                                                              drift: 0.1) })
    end

    def start
        Sensorium::Filter::State.new(location: "room",
                                     quantity: "temperature", at: AT,
                                     value: 20.0, variance: 0.01)
    end

    def fused(value, sigma, at:)
        Sensorium::Fusion::Fused.new(
            location: "room", quantity: "temperature", at:, value:, sigma:,
            inside: Sensorium::Estimate.new(value:, sigma:), reference: nil,
            corrected: !sigma.nil?, parts: []
        )
    end

    def with_outside(snap, value)
        reading = Sensorium::Reading.new(time: AT + HOUR, location: nil,
                                         device: "outside", value:)
        snap.with(at: AT + HOUR,
                  latest: snap.latest.merge([nil, "outside"] => reading))
    end

    def model
        Sensorium::Dynamics::Model.new(location: "room",
                                       quantity: "temperature",
                                       regime: "winter", a: 0.01, b: {},
                                       c: 0.0, q: 0.04, bin: 600,
                                       steps: 1000)
    end
end
