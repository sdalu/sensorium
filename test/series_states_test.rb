# frozen_string_literal: true

require "test_helper"

# Per-level spreads of a Series: a sensor noisier in sun gets the wider
# spread only while the series is above its median. Made-up bins: the
# PV inverter's power swinging between 100 and 2900 W around 1500, a
# sensor 0.4 °C higher per kW, its noise uniform over ±0.4 above
# 1500 W, ±0.04 below.
class SeriesStatesTest < Minitest::Test
    BINS  = (0...2000).to_a
    SETUP = Sensorium::Setup.new(quantity: Sensorium::Presets::TEMPERATURE,
                                 gain: false, rate: false)

    def setup
        solar = BINS.to_h { [it, 1500 + (1400 * Math.sin(it / 23.0))] }
        fit = Sensorium::Fit.new(diffs(solar), SETUP,
                                 levels: BINS.to_h { [it, 20] },
                                 series: { "solar" => solar })
        @model = fit.model
        @offset = offset(fit)
    end

    def test_the_series_is_a_term
        assert_in_delta 4e-4, @model.series.fetch("solar"), 2e-5
    end

    def test_the_spreads_are_kept_per_level
        high = @offset.states.fetch("solar:high")
        low = @offset.states.fetch("solar:low")
        assert_in_delta 0.64, high[1] - high[0], 0.08
        assert_in_delta 0.064, low[1] - low[0], 0.01
        [high, low].each { assert_in_delta 1500, it[2], 30 }
    end

    def test_the_wider_sigma_only_above_the_median
        sunny = @offset.correct(21.0, values: { "solar" => 2500 })
        dull = @offset.correct(20.5, values: { "solar" => 500 })
        assert_in_delta 0.64 / Sensorium::P10_P90, sunny.sigma, 0.03
        assert_in_delta 0.064 / Sensorium::P10_P90, dull.sigma, 0.004
    end

    # Without the per-level spreads, the one spread of every bin.
    def test_without_them_todays_spread
        bare = @offset.with(states: {})
        [500, 2500].each do |watts|
            assert_in_delta @offset.sigma,
                            bare.correct(21.0, values: { "solar" => watts })
                                .sigma
        end
    end

    private

    def diffs(solar)
        random = Random.new(4)
        BINS.to_h do |bin|
            noise = (random.rand - 0.5) * (solar[bin] > 1500 ? 0.8 : 0.08)
            [bin, 0.1 + (4e-4 * solar[bin]) + noise]
        end
    end

    def offset(fit)
        Sensorium::Offset.new(location: "a", device: "s",
                              quantity: "temperature", regime: "winter",
                              reference: "r",
                              **Sensorium::Learned.values(@model, fit.plain),
                              **fit.states(@model))
    end
end
