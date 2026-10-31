# frozen_string_literal: true

require "test_helper"
require "support/fake_house"

# What the Learner refuses: a mode seen too little to be a shift, a
# sensor that says it is no neighbour.
class LearnerGuardsTest < Minitest::Test
    # The aircon ran 180 bins in room-a: under 200, no shift at all.
    def test_a_mode_seen_too_little_is_no_shift
        learned = Sensorium::Learner.new(
            FakeHouse.new, Sensorium::Presets.room(min_shift: 200),
            from: FakeHouse::START, to: FakeHouse::START + (10 * 86_400)
        ).learn
        assert_empty learned.shifts
    end

    def test_a_sensor_that_is_no_neighbour_is_never_one
        series = Sensorium::Series.new(600)
        data = { %w[b g1] => { 0 => 10.0 }, %w[b tado] => { 0 => 12.0 },
                 [nil, "outside"] => { 0 => 5.0 } }
        sensors = [Sensorium::Sensor.new(name: "g1", location: "b"),
                   Sensorium::Sensor.new(name: "tado", location: "b",
                                         neighbour: false)]
        gaps = Sensorium::Learner::Neighbours.new(series, 3600, sensors, data)
                                             .gaps("a", { 0 => 20.0 })
        assert_equal %w[b/g1 outside], gaps.keys.sort
        assert_in_delta 15.0, gaps["outside"][0]
    end
end
