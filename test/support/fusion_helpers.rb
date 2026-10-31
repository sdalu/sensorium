# frozen_string_literal: true

# A made-up room for Fusion's tests: the ceiling sensor "ceil" (σ 0.1),
# tado 1 °C low (σ 0.2), Airzone 1 °C high (σ 0.08), on 10 January.
module FusionHelpers
    AT = Time.utc(2026, 1, 10, 12)

    private

    # readings: { device => value or [value, age in seconds, context] };
    # learning: the Fusion's setup, shifts, locations.
    def fuse(readings, location: "room", modes: {}, context: {}, **learning)
        fusion(**learning).location(location,
                                    snapshot(location, readings, modes),
                                    context:)
    end

    def fusion(setup: Sensorium::Presets.room, shifts: [], locations: {})
        Sensorium::Fusion.new(setup, offsets:, shifts:, locations:)
    end

    def snapshot(location, readings, modes = {})
        latest = readings.to_h do |device, (value, age, context)|
            [[location, device],
             Sensorium::Reading.new(time: AT - age.to_i, location:, device:,
                                    value:, context: context || {})]
        end
        Sensorium::Snapshot.new(at: AT, latest:, modes:)
    end

    def offsets
        [offset("tado", -1.0, 0.25), offset("airzone", 1.0, 0.1)]
    end

    def offset(device, constant, half, quantity: "temperature")
        Sensorium::Offset.new(location: "room", device:, quantity:,
                              regime: "winter", reference: "ceil",
                              constant:, switches: {}, gain: nil,
                              neighbour: nil, coefficient: nil, p10: -half,
                              p90: half, samples: 1000, plain: constant,
                              plain_p10: -half, plain_p90: half)
    end

    def weight(fused, device) = part(fused, device).weight
    def note(fused, device) = part(fused, device).note
    def part(fused, device) = fused.parts.find { it.part.device == device }
end
