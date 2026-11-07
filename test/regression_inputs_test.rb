# frozen_string_literal: true

require "test_helper"

# What Regression.load reads from a source: the quantity's readings,
# summed per bin and added across devices, and the regressors from the
# events, named by influence and location. Every value is made up.
class RegressionInputsTest < Minitest::Test
    T0   = Time.utc(2026, 1, 5)
    HOUR = 3600
    GAS  = Sensorium::Quantity.new(name: "gas", unit: "kWh", sigma: 0.1,
                                   drift: 1.0)
    VALVE  = Sensorium::Influence::Series.new(name: "valve",
                                              scope: :location, hold: 0)
    BURNER = Sensorium::Influence::Switch.new(name: "burner", hold: 0)

    # Two meters, each a reading every half hour; a valve per room; the
    # burner on in the second hour.
    Source = Struct.new(:readings_by, :events_by) do
        def readings(_quantity, from, to, devices)
            readings_by.select do |one|
                (from..to).cover?(one.time) &&
                    (devices.nil? || devices.include?(one.device))
            end
        end

        def events(name, from, to)
            events_by.fetch(name, []).select { (from..to).cover?(it.first) }
        end
    end

    def setup
        readings = %w[main annex].product([0, 1800, 3600, 5400])
                                 .map { |device, at| reading(device, at) }
        valve = [[T0, "a", 20], [T0 + HOUR, "a", 60], [T0, "b", 10]]
        @source = Source.new(readings, { "valve" => valve,
                                         "burner" => [[T0 + HOUR, nil, 1]] })
        @setup = Sensorium::Setup.new(quantity: GAS, bin: HOUR,
                                      influences: [VALVE, BURNER])
    end

    def test_the_readings_summed_and_the_meters_added
        assert_equal({ T0.to_i => 6.0, (T0 + HOUR).to_i => 6.0 }, load[:y])
    end

    def test_a_meter_read_alone
        assert_equal({ T0.to_i => 2.0, (T0 + HOUR).to_i => 2.0 },
                     load(devices: %w[annex])[:y])
    end

    def test_the_mean_of_the_readings
        assert_equal({ T0.to_i => 3.0, (T0 + HOUR).to_i => 3.0 },
                     load(total: false)[:y])
    end

    def test_a_level_per_location_and_a_switch_site_wide
        regressors = load[:regressors]
        assert_equal %w[burner valve/a valve/b], regressors.keys.sort
        assert_equal({ T0.to_i => 20.0, (T0 + HOUR).to_i => 60.0 },
                     regressors["valve/a"])
        assert_equal({ T0.to_i => 0.0, (T0 + HOUR).to_i => 1.0 },
                     regressors["burner"])
    end

    # The rooms' valves summed, over the bins both have, beside each.
    def test_a_location_s_influence_pooled
        regressors = load(pooled: true)[:regressors]
        assert_equal({ T0.to_i => 30.0 }, regressors["valve"])
        assert regressors.key?("valve/a")
        refute load[:regressors].key?("valve")
    end

    def test_an_unknown_option_is_refused
        assert_raises(ArgumentError) { load(pool: true) }
    end

    private

    # The main meter reads 2 kWh, the annex 1, each half hour.
    def reading(device, at)
        Sensorium::Reading.new(time: T0 + at, location: nil, device:,
                               value: device == "main" ? 2.0 : 1.0)
    end

    def load(**)
        Sensorium::Regression.load(@source, @setup, from: T0,
                                                    to: T0 + 7199, **)
    end
end
