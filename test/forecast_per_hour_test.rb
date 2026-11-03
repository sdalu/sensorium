# frozen_string_literal: true

require "test_helper"

# Dynamics::Forecast#per_hour: q is a variance per hour, so the mean
# square error over a horizon rounded to whole bins is scaled by that
# horizon's hours. A bin of 2400 s makes the hour two bins, 4/3 h: a
# square error of 1 over it is 0.75 per hour.
class ForecastPerHourTest < Minitest::Test
    def test_a_rounded_horizon_is_scaled_to_an_hour
        model = Sensorium::Dynamics::Model.new(
            location: "room", quantity: "temperature", regime: "winter",
            a: 0.0, c: 0.0, q: 0.0, bin: 2400, steps: 0
        )
        forecast = Sensorium::Dynamics::Forecast.new(
            { 0 => 20.0, 4800 => 21.0 }, nil, {}
        )
        assert_in_delta 1.0, forecast.mean_square(model, [0], 1.0), 1e-12
        assert_in_delta 0.75, forecast.per_hour(model, [0], 1.0), 1e-12
    end
end
