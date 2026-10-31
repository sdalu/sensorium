# frozen_string_literal: true

require "test_helper"
require "support/fusion_helpers"

# Relative humidity fused as absolute humidity: a sensor warmer than the
# room reads lower for the same air.
class HumidityTest < Minitest::Test
    include FusionHelpers

    AH    = Sensorium::Transform::AbsoluteHumidity
    SETUP = Sensorium::Presets.room(Sensorium::Presets::HUMIDITY)
    ROOM  = { temperature: 20.0 }.freeze

    def test_there_and_back
        inside = AH.forward(50.0, ROOM)
        assert_in_delta 8.64, inside, 0.01
        assert_in_delta 50.0, AH.inverse(inside, ROOM)
        assert_nil AH.forward(50.0, {})
    end

    # The same air (50 % at 20 °C) read by a sensor at 22 °C: 44.5 %.
    def test_a_warmer_sensor_reads_lower
        assert_in_delta 44.5, warm, 0.1
    end

    # Corrected as absolute humidity, both say 50 % at the room's 20 °C.
    def test_a_warmer_sensor_agrees_once_transformed
        fused = fuse({ "ceil" => [50.0, 0, ROOM],
                       "tado" => [warm, 0, { temperature: 22.0 }] },
                     setup: SETUP, context: ROOM)
        assert_in_delta 50.0, fused.value, 0.01
        assert_in_delta 50.0, part(fused, "tado").value, 0.01
        assert_in_delta fused.inside.sigma * 50.0 / fused.inside.value,
                        fused.sigma
    end

    def test_without_the_sensors_temperature_it_does_not_count
        fused = fuse({ "ceil" => [50.0, 0, ROOM], "tado" => 45.0 },
                     setup: SETUP, context: ROOM)
        assert_equal "no context", note(fused, "tado")
        assert_in_delta 50.0, fused.value
    end

    # No temperature for the room: the absolute humidity alone.
    def test_without_the_rooms_temperature_no_value
        fused = fuse({ "ceil" => [50.0, 0, ROOM] }, setup: SETUP)
        assert_nil fused.value
        assert_nil fused.sigma
        assert_in_delta 8.64, fused.inside.value, 0.01
    end

    private

    def warm = 100.0 * AH.forward(50.0, ROOM) / AH.saturation(22.0)

    def offsets
        [offset("tado", 0.0, 0.1, quantity: "humidity")]
    end
end
