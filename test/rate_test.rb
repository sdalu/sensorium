# frozen_string_literal: true

require "test_helper"

# The rate term: a sensor slower than the reference reads behind it by
# about its lag × dr/dt (r in units per hour). Every value is made up.
class RateTest < Minitest::Test
    BINS  = (0...1000).map { it * 600 }
    SETUP = Sensorium::Setup.new(quantity: Sensorium::Presets::TEMPERATURE)

    def setup
        @reference = BINS.to_h { [it, 20 + (3 * Math.sin(it / 20_000.0))] }
        @rates = Sensorium::Series.new(600).rates(@reference)
        random = Random.new(5)
        @noise = BINS.to_h { [it, (random.rand - 0.5) * 0.02] }
    end

    # Central differences, one bin each side, per hour.
    def test_the_rate_of_a_series
        rates = Sensorium::Series.new(600)
                                 .rates({ 0 => 1.0, 600 => 2.0, 1200 => 4.0,
                                          2400 => 5.0 })
        assert_equal [600], rates.keys
        assert_in_delta 9.0, rates[600]
    end

    # 30 minutes behind the reference.
    def test_a_slow_sensor_earns_a_rate
        model = fit { -0.5 * @rates[it] }
        assert_in_delta(-0.5, model.rate, 0.02)
    end

    def test_a_sensor_that_does_not_lag_earns_none
        assert_nil fit { 0.3 }.rate
    end

    def test_no_rate_when_the_setup_says_so
        assert_nil fit(SETUP.with(rate: false)) { -0.5 * @rates[it] }.rate
    end

    # sensor - r = 0.2 - 0.5 × dr/dt: rising at 3 °C/h, it reads 1.3
    # under the reference.
    def test_the_rate_is_solved_for
        found = offset.correct(20.0 - 1.3, dr_dt: 3.0)
        assert_in_delta 20.0, found.value
    end

    # dr/dt not known: the plain offset.
    def test_without_the_rate_the_plain_offset
        found = offset.correct(18.7)
        assert_in_delta 18.7 - 0.25, found.value
        assert_in_delta 1.0 / Sensorium::P10_P90, found.sigma
    end

    private

    def fit(setup = SETUP)
        diffs = @rates.keys.to_h { [it, yield(it) + @noise[it]] }
        Sensorium::Fit.new(diffs, setup, levels: @reference,
                                         rates: @rates).model
    end

    def offset
        Sensorium::Offset.new(location: "a", device: "s",
                              quantity: "temperature", regime: "winter",
                              reference: "r", constant: 0.2, switches: {},
                              gain: nil, neighbour: nil, coefficient: nil,
                              rate: -0.5, p10: -0.1, p90: 0.1,
                              samples: 1000, plain: 0.25, plain_p10: -0.5,
                              plain_p90: 0.5)
    end
end
