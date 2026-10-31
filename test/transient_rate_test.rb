# frozen_string_literal: true

require "test_helper"
require "support/one_sensor"

# Thresholds as quantiles at Setup#transient_rate: a stepped sensor's
# single step is no event, a heavy-tailed sensor fires at about the
# rate on calm data it was not learned from.
class TransientRateTest < Minitest::Test
    SIZE  = 1440 # ten days
    SETUP = Sensorium::Setup.new(quantity: Sensorium::Presets::TEMPERATURE)

    # 0.1 °C up five times and down five times in ten days: at two a
    # day, the quantiles are 0, raised to the step.
    def test_a_stepped_sensors_threshold_is_its_step
        own = stepped.own
        own.each_value do |threshold|
            assert_in_delta 0.1, threshold.rise, 1e-5
            assert_in_delta(-0.1, threshold.fall, 1e-5)
        end
    end

    def test_a_single_step_is_no_event
        assert_empty events(20.0, 20.1)
        assert_empty events(20.1, 20.0)
    end

    def test_a_five_step_fall_is_an_event
        found = events(20.0, 19.5)
        assert_equal [:fall], found.map(&:direction).uniq
        assert_in_delta 5.0, found.first.z, 1e-3
    end

    # 5 a day over ten days: some 50 events per window and direction,
    # learned on one draw, counted on another.
    def test_a_heavy_tailed_sensor_fires_at_about_the_rate
        setup = SETUP.with(transient_rate: 5)
        house = OneSensor.new(heavy(1))
        profiles = Sensorium::Transient.learn(house, setup, from: house.time(0),
                                                            to: house.last)
        counts = fired(setup, profiles, OneSensor.new(heavy(2)))
        assert_equal 4, counts.size
        counts.each_value { assert_includes 25..100, it }
    end

    private

    def stepped
        values = SIZE.times.map { (20 + (0.1 * level(it))).round(2) }
        house = OneSensor.new(values)
        Sensorium::Transient.learn(house, SETUP.with(transient_rate: 2),
                                   from: house.time(0), to: house.last)
                            .first
    end

    # Up a step at each 200th reading, down at 100 after.
    def level(index)
        (1..5).count { index >= it * 200 } -
            (1..5).count { index >= (it * 200) + 100 }
    end

    # The events of the stepped sensor reading `before` then `now`, ten
    # minutes apart.
    def events(before, now)
        house = OneSensor.new([before, now])
        Sensorium::Transient::Detector.new(SETUP, profiles: [stepped])
                                      .events(house.snapshot(1))
    end

    # 20 °C, with 95 % of readings off by up to ±0.05, 5 % by up to ±1.
    def heavy(seed)
        random = Random.new(seed)
        SIZE.times.map do
            wide = random.rand < 0.05 ? 1.0 : 0.05
            20 + ((random.rand - 0.5) * 2 * wide)
        end
    end

    # { [window, direction] => events } over every reading.
    def fired(setup, profiles, house)
        detector = Sensorium::Transient::Detector.new(setup, profiles:)
        (6...house.size).flat_map { detector.events(house.snapshot(it)) }
                        .group_by { [it.window, it.direction] }
                        .transform_values(&:size)
    end
end
