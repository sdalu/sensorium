# frozen_string_literal: true

require "test_helper"

# Setup#recent: an offset's constant recentred on its last bins, each
# bin's weight halved by every recent seconds of its age. A sensor 1.0
# below its ceiling for eight days, then 0.4 below for two.
class RecentConstantTest < Minitest::Test
    START = Time.utc(2026, 1, 5)
    STEP  = 600
    DAYS  = 10

    # The sensor "s" and its ceiling "ref" in "room".
    class Source
        def initialize
            random = Random.new(7)
            @all = (0...(DAYS * 86_400 / STEP)).flat_map do |index|
                time = START + (index * STEP)
                ref = 20.0 + random.rand(-0.05..0.05)
                gap = index < 8 * 86_400 / STEP ? -1.0 : -0.4
                [reading(time, "ref", ref),
                 reading(time, "s", ref + gap + random.rand(-0.05..0.05))]
            end
        end

        def sensors(_quantity)
            [Sensorium::Sensor.new(name: "ref", location: "room",
                                   tags: ["ceiling"]),
             Sensorium::Sensor.new(name: "s", location: "room")]
        end

        def readings(_quantity, from, to, _devices = nil)
            @all.select { (from..to).cover?(it.time) }
        end

        private

        def reading(time, device, value)
            Sensorium::Reading.new(time:, location: "room", device:, value:)
        end
    end

    def test_without_recent_every_bin_weighs_alike
        offset = learn(nil)
        assert_in_delta(-1.0, offset.constant, 0.05)
        assert_in_delta(-1.0, offset.plain, 0.05)
    end

    # Halved every day, the last two days weigh three quarters.
    def test_a_short_half_life_takes_the_last_days
        offset = learn(86_400)
        assert_in_delta(-0.4, offset.constant, 0.05)
        assert_in_delta(-0.4, offset.plain, 0.05)
    end

    # Halved every week, the last two days weigh less than a half.
    def test_a_long_half_life_keeps_the_standing_level
        assert_in_delta(-1.0, learn(7 * 86_400).constant, 0.05)
    end

    def test_the_widths_are_what_the_recentred_constant_leaves
        offset = learn(86_400)
        assert_in_delta 0.6, offset.p10.abs, 0.1
    end

    private

    def learn(recent)
        setup = Sensorium::Presets.room.with(recent:)
        Sensorium::Learner.new(Source.new, setup, from: START,
                                                  to: START + (DAYS * 86_400))
                          .learn.offsets.fetch(0)
    end
end
