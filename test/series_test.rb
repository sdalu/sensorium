# frozen_string_literal: true

require "test_helper"

# A continuous influence (Influence::Series): the PV inverter's power,
# learned as coefficient × value. Every value is made up.
class SeriesTest < Minitest::Test
    BINS  = (0...1000).to_a
    SETUP = Sensorium::Setup.new(quantity: Sensorium::Presets::TEMPERATURE)
    SOLAR = Sensorium::Influence::Series.new(name: :solar, hold: 1200)

    def setup
        @reference = BINS.to_h { [it, 20 + (3 * Math.sin(it / 50.0))] }
        @solar = BINS.to_h { [it, [3000 * Math.sin(it / 23.0), 0].max] }
        random = Random.new(9)
        @noise = BINS.to_h { [it, (random.rand - 0.5) * 0.02] }
    end

    def test_a_series_is_named_by_a_string
        assert_equal "solar", SOLAR.name
        assert_equal :site, SOLAR.scope
    end

    # 0.4 °C more per kW.
    def test_a_sensor_in_the_sun_earns_the_series
        model = fit(series: { "solar" => @solar }) { 0.1 + (4e-4 * @solar[it]) }
        assert_in_delta 4e-4, model.series.fetch("solar"), 1e-5
        assert_in_delta 0.1, model.constant, 0.01
    end

    def test_a_sensor_in_the_shade_does_not
        model = fit(series: { "solar" => @solar }) { 0.1 }
        assert_empty model.series
    end

    def test_a_series_must_cover_most_bins
        half = @solar.select { |bin, _| bin.even? }
        model = fit(series: { "solar" => half }) { 4e-4 * @solar[it] }
        assert_empty model.series
    end

    # Binned as the mean per bin, carried `hold` seconds.
    def test_the_timeline_bins_and_carries_a_series
        source = Events.new([[0, nil, 100], [300, nil, 300], [600, nil, 50],
                             [6000, "x", 7]])
        timeline = Sensorium::Timeline.new(SETUP.with(influences: [SOLAR]),
                                           source, Time.at(0), Time.at(9000))
        solar = timeline.series("room").fetch("solar")
        assert_equal({ 0 => 200.0, 600 => 50.0, 1200 => 50.0, 1800 => 50.0,
                       6000 => 7.0, 6600 => 7.0, 7200 => 7.0 }, solar)
    end

    # 0.2 + 4e-4 × 2000 W.
    def test_the_series_is_solved_for
        assert_in_delta 20.0, offset.correct(21.0, values: { "solar" => 2000 })
                                    .value
    end

    def test_without_its_value_the_plain_offset
        found = offset.correct(21.0, values: {})
        assert_in_delta 21.0 - 0.6, found.value
        assert_in_delta 1.0 / Sensorium::P10_P90, found.sigma
    end

    private

    # A source telling only events.
    Events = Struct.new(:list) do
        def events(_name, from, to)
            list.select { (from.to_i..to.to_i).cover?(it.first) }
                .map { |time, *rest| [Time.at(time), *rest] }
        end
    end

    def fit(series:)
        diffs = BINS.to_h { [it, yield(it) + @noise[it]] }
        Sensorium::Fit.new(diffs, SETUP, levels: @reference, series:).model
    end

    def offset
        Sensorium::Offset.new(location: "a", device: "s",
                              quantity: "temperature", regime: "winter",
                              reference: "r", constant: 0.2, switches: {},
                              series: { "solar" => 4e-4 }, gain: nil,
                              neighbour: nil, coefficient: nil, p10: -0.1,
                              p90: 0.1, samples: 1000, plain: 0.6,
                              plain_p10: -0.5, plain_p90: 0.5)
    end
end
