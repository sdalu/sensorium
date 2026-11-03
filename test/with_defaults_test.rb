# frozen_string_literal: true

require "test_helper"

# Data#with runs initialize again with every member given: the defaults
# derived from another member (a Quantity's floor and track_q from its
# sigma, a Setup's counts and transient windows from its bin) follow the
# member changed, as a fresh one's would, and a value set stays.
class WithDefaultsTest < Minitest::Test
    # Quantity: "floor ... (a quarter of sigma unless set)", "track_q
    # ... ((sigma/2)² in half a day unless set)".
    def test_a_quantity_with_another_sigma_keeps_its_derived_defaults
        quantity = Sensorium::Presets::TEMPERATURE.with(sigma: 0.4)
        fresh = Sensorium::Quantity.new(name: "temperature", unit: "°C",
                                        sigma: 0.4, drift: 1.0)
        assert_in_delta fresh.floor, quantity.floor
        assert_in_delta fresh.track_q, quantity.track_q
    end

    # Setup: "min_samples ... (500 of ten minutes; by default the same
    # time with another bin)"; "the transient windows are one bin and
    # two unless given".
    def test_a_setup_with_another_bin_keeps_its_derived_defaults
        setup = Sensorium::Presets.room.with(bin: 300)
        fresh = Sensorium::Presets.room(bin: 300)
        assert_equal [fresh.min_samples, fresh.min_shift, fresh.min_part,
                      fresh.transient_windows],
                     [setup.min_samples, setup.min_shift, setup.min_part,
                      setup.transient_windows]
    end

    def test_a_setup_with_a_bin_of_fifteen_minutes_takes_its_windows
        assert_equal [900, 1800],
                     Sensorium::Presets.room.with(bin: 900).transient_windows
    end

    def test_a_value_set_stays_with_another_member
        quantity = Sensorium::Quantity.new(name: "t", sigma: 0.1, drift: 1.0,
                                           floor: 0.05, track_q: 0.01)
                                      .with(sigma: 0.4)
        assert_equal [0.05, 0.01], [quantity.floor, quantity.track_q]
        setup = Sensorium::Presets.room(min_samples: 42,
                                        transient_windows: [1800])
                                  .with(bin: 900)
        assert_equal [42, [1800]],
                     [setup.min_samples, setup.transient_windows]
    end
end
