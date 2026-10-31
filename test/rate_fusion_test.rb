# frozen_string_literal: true

require "test_helper"
require "support/fusion_helpers"

# dr/dt at fusion: from the reference's two latest readings within the
# location's max_age; the plain offset when there are not two. Learned
# on a made-up room whose sensor reads 30 minutes behind its ceiling.
class RateFusionTest < Minitest::Test
    include FusionHelpers

    # The ceiling rose by 0.5 in the last 10 minutes: 3 °C/h; slow
    # reads 1.5 under it.
    def test_the_rate_from_the_references_latest_readings
        fused = fused_slow([[20.0, 600], [20.5, 0]], 19.0)
        assert_in_delta 20.5, part(fused, "slow").value
    end

    def test_readings_older_than_max_age_give_no_rate
        fused = fused_slow([[20.0, 7200], [20.5, 5400]], 19.0)
        assert_in_delta 19.0, part(fused, "slow").value
    end

    def test_one_reading_gives_no_rate
        fused = fused_slow([[20.5, 0]], 19.0)
        assert_in_delta 19.0, part(fused, "slow").value
    end

    def test_a_slow_sensor_is_learned_with_a_rate
        slow = Sensorium::Learner.new(SlowRoom.new, SlowRoom::SETUP,
                                      from: SlowRoom::START,
                                      to: SlowRoom::START + (10 * 86_400))
                                 .learn.offsets.first
        assert_equal "slow", slow.device
        assert_in_delta(-0.5, slow.rate, 0.05)
    end

    private

    # ceiling: [[value, age]], the latest last.
    def fused_slow(ceiling, slow)
        history = ceiling.map { reading("ceil", *it) }
        latest = { %w[room ceil] => history.last,
                   %w[room slow] => reading("slow", slow, 0) }
        snap = Sensorium::Snapshot.new(at: AT, latest:,
                                       history: { %w[room ceil] => history })
        fusion.location("room", snap)
    end

    def reading(device, value, age)
        Sensorium::Reading.new(time: AT - age, location: "room", device:,
                               value:)
    end

    def offsets
        [offset("slow", 0.0, 0.1).with(rate: -0.5)]
    end

    # A room whose "slow" sensor reads 30 minutes behind its ceiling.
    class SlowRoom
        START = Time.utc(2026, 1, 5)
        SETUP = Sensorium::Setup.new(quantity: Sensorium::Presets::TEMPERATURE,
                                     places: %w[ceiling])

        def sensors(_quantity)
            [Sensorium::Sensor.new(name: "ceil", location: "room",
                                   tags: %w[ceiling]),
             Sensorium::Sensor.new(name: "slow", location: "room")]
        end

        def readings(_quantity, from, to, _devices)
            times = (0...1440).map { START + (it * 600) }.grep(from..to)
            times.flat_map { [read("ceil", it, 0), read("slow", it, 1800)] }
        end

        private

        def read(device, time, lag)
            value = 20 + (3 * Math.sin((time.to_i - lag) / 20_000.0))
            Sensorium::Reading.new(time:, location: "room", device:, value:)
        end
    end
end
