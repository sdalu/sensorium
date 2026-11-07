# frozen_string_literal: true

require "test_helper"
require "support/fake_house"

# Recent: a sensor's gap to its reference over the last days, one per
# Mode state with enough bins (FakeHouse: room-a's tado 0.9 below its
# ceiling; blue has no reference; few's tado read 20 times only).
class RecentTest < Minitest::Test
    def setup
        house = FakeHouse.new
        at = FakeHouse::START + (FakeHouse::DAYS * 86_400)
        @recents = Sensorium::Recent.learn(house, Sensorium::Presets.room,
                                           at:)
    end

    def test_the_gap_as_it_stood_lately
        tado = Sensorium::Recent.find(@recents, "room-a", "tado", [])
        assert_in_delta(-0.9, tado.gap, 0.1)
        assert_operator tado.samples, :>=, Sensorium::Recent::MIN
        assert_in_delta 20.0 + tado.gap, tado.predict(20.0).value
        assert_in_delta tado.sigma, tado.predict(20.0).sigma
    end

    # No reference, no gap; too few bins, none either; a reference is
    # no sensor of its own.
    def test_only_the_sensors_with_a_reference_and_enough_bins
        assert_nil Sensorium::Recent.find(@recents, "blue", "tado", [])
        assert_nil Sensorium::Recent.find(@recents, "few", "tado", [])
        assert_nil Sensorium::Recent.find(@recents, "room-a", "ceil-a", [])
    end

    def test_what_holds_is_named_as_a_shift_is
        assert_equal "-", Sensorium::Recent.named([])
        assert_equal "aircon+fan=cooling+on",
                     Sensorium::Recent.named([%w[fan on], %w[aircon cooling]])
    end
end
