# frozen_string_literal: true

require "test_helper"

# Quantity#inward: "The readings taken into the transform's space, those
# it cannot take left out." A humidity reading without a value, or with
# a nil context, is left out as a temperature's is; and no value comes
# back from either.
class HumidityContextTest < Minitest::Test
    AT = Time.at(1_700_000_000)

    def test_a_humidity_reading_with_no_context_is_left_out
        reading = Sensorium::Reading.new(time: AT, location: "bath",
                                         device: "damp", value: 60.0,
                                         context: nil)
        assert_empty Sensorium::Presets::HUMIDITY.inward([reading])
    end

    def test_a_humidity_reading_with_no_value_is_left_out
        reading = Sensorium::Reading.new(time: AT, location: "bath",
                                         device: "damp", value: nil,
                                         context: { temperature: 20.0 })
        assert_empty Sensorium::Presets::TEMPERATURE.inward([reading])
        assert_empty Sensorium::Presets::HUMIDITY.inward([reading])
    end

    def test_no_humidity_comes_back_without_a_value_or_a_context
        humidity = Sensorium::Transform::AbsoluteHumidity
        assert_nil humidity.inverse(8.0, nil)
        assert_nil humidity.inverse(nil, { temperature: 20.0 })
    end
end
