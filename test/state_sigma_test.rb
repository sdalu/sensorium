# frozen_string_literal: true

require "test_helper"

# Per-state σ: a sensor noisier while the radiators run gets the wider
# spread only while they do. A made-up room, ten days of a reading
# every bin: the ceiling's reference at 20, a sensor 0.5 above it,
# 1.0 above while the heating is on (six hours in twelve), its noise
# uniform over ±0.05 when off and ±0.5 when on.
class StateSigmaTest < Minitest::Test
    START = Time.utc(2026, 1, 5)
    STEP  = 600
    SIZE  = 1440
    HEATING = Sensorium::Influence::Switch.new(name: "heating", hold: 0)

    # A source of the room above.
    class Room
        def initialize
            random = Random.new(11)
            @rows = (0...SIZE).map do |index|
                on = index % 72 < 36
                noise = (random.rand - 0.5) * (on ? 1.0 : 0.1)
                [START + (index * STEP), on, 20.5 + (on ? 0.5 : 0) + noise]
            end
        end

        def sensors(_quantity)
            [Sensorium::Sensor.new(name: "ceil", location: "room",
                                   tags: %w[ceiling]),
             Sensorium::Sensor.new(name: "wall", location: "room")]
        end

        def readings(_quantity, from, to, _devices)
            @rows.select { (from..to).cover?(it.first) }
                 .flat_map do |time, _, value|
                     [reading(time, "ceil", 20.0), reading(time, "wall", value)]
                 end
        end

        def events(_name, from, to)
            @rows.filter_map do |time, on, _|
                [time, nil, 1] if on && (from..to).cover?(time)
            end
        end

        private

        def reading(time, device, value)
            Sensorium::Reading.new(time:, location: "room", device:, value:)
        end
    end

    def setup
        setup = Sensorium::Setup.new(quantity: Sensorium::Presets::TEMPERATURE,
                                     influences: [HEATING], places: %w[ceiling])
        learner = Sensorium::Learner.new(Room.new, setup,
                                         from: START,
                                         to: START + (SIZE * STEP))
        @offset = learner.learn.offsets.first
    end

    def test_the_spreads_are_kept_per_state
        assert_in_delta 0.5, @offset.switches.fetch("heating"), 0.05
        low, high = @offset.states.fetch("heating")
        assert_in_delta 0.8, high - low, 0.1
        assert_in_delta 0.08, @offset.off_p90 - @offset.off_p10, 0.02
    end

    def test_the_wider_sigma_only_while_on
        on = @offset.correct(21.0, on: %w[heating])
        off = @offset.correct(20.5)
        assert_in_delta 0.8 / Sensorium::P10_P90, on.sigma, 0.04
        assert_in_delta 0.08 / Sensorium::P10_P90, off.sigma, 0.008
    end

    # Without the per-state spreads, the one spread of every bin.
    def test_without_them_todays_spread
        bare = @offset.with(states: {}, off_p10: nil, off_p90: nil)
        assert_in_delta @offset.sigma, bare.correct(21.0, on: %w[heating])
                                           .sigma
        assert_in_delta @offset.sigma, bare.correct(20.5).sigma
    end

    # A Switch on whose spread was not kept (too few bins) counts as
    # the one spread of every bin.
    def test_a_switch_on_without_its_spread
        some = @offset.with(states: {})
        assert_in_delta @offset.sigma,
                        some.correct(21.0, on: %w[heating]).sigma
        assert_in_delta 0.08 / Sensorium::P10_P90, some.correct(20.5).sigma,
                        0.008
    end
end
