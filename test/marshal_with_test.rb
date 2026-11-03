# frozen_string_literal: true

require "test_helper"

# A Quantity and a Setup are values: they round-trip through Marshal
# (a cache, a worker process), and the copy answers with as the
# original does.
class MarshalWithTest < Minitest::Test
    def test_quantity_round_trips
        quantity = Sensorium::Presets::TEMPERATURE
        copy = Marshal.load(Marshal.dump(quantity))
        assert_equal quantity, copy
        assert_in_delta 0.25, copy.with(sigma: 1.0).floor
    end

    def test_setup_round_trips
        setup = Sensorium::Presets.room
        copy = Marshal.load(Marshal.dump(setup))
        assert_equal setup, copy
        assert_equal [900, 1800], copy.with(bin: 900).transient_windows
    end
end
