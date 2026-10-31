# frozen_string_literal: true

require "test_helper"

# Dynamics.learn on made-up rooms: one that follows the outside and its
# radiators, one that runs away from the outside, one seen too briefly.
class DynamicsTest < Minitest::Test
    START = Time.utc(2026, 1, 5)
    STEP  = 600

    def test_a_room_recovers_its_outside_and_heating_terms
        model = learn(Room.new(START, 1440)).first
        assert_equal %w[room all], [model.location, model.regime]
        assert_in_delta 0.1, model.a, 0.01
        assert_in_delta 0.5, model.b.fetch("heating"), 0.05
        assert_in_delta 0.0, model.c, 0.05
    end

    def test_the_noise_is_kept_per_hour
        model = learn(Room.new(START, 1440)).first
        # Noise uniform over ±0.05 per step: 0.1² / 12, six steps an hour.
        assert_in_delta 6 * (0.01 / 12), model.q, 0.002
        assert_equal 600, model.bin
        assert_operator model.steps, :>=, 1400
    end

    def test_an_unstable_room_gives_no_model
        assert_empty learn(Room.new(START, 1440, a: -0.01))
    end

    def test_too_short_a_history_gives_no_model
        assert_empty learn(Room.new(START, 300))
    end

    def test_without_an_outside_there_is_no_outside_term
        model = learn(Room.new(START, 1440), outside: nil).first
        assert_in_delta 0.0, model.a
        assert model.b.key?("heating")
    end

    private

    def learn(room, outside: "outside")
        setup = Sensorium::Setup.new(quantity: Sensorium::Presets::TEMPERATURE,
                                     places: %w[ceiling], outside:,
                                     influences: [Room::HEATING])
        Sensorium::Dynamics.learn(room, setup, from: START,
                                               to: START + (room.size * STEP))
    end

    # r(t + bin) - r(t) = a × (outside - r) + 0.5 × heating + noise, the
    # outside a daily wave, the radiators on three hours in six.
    class Room
        HEATING = Sensorium::Influence::Switch.new(name: "heating", hold: 0)

        attr_reader :size

        def initialize(start, size, a: 0.1)
            @start  = start
            @size   = size
            @random = Random.new(7)
            build(a)
        end

        def sensors(_quantity)
            [Sensorium::Sensor.new(name: "ceil", location: "room",
                                   tags: %w[ceiling])]
        end

        def readings(_quantity, from, to, _devices)
            @readings.select { (from..to).cover?(it.time) }
        end

        def externals(_quantity, from, to)
            @outside.select { (from..to).cover?(it.time) }
        end

        def events(_name, from, to)
            @heating.select { (from..to).cover?(it.first) }
        end

        private

        def build(a)
            @readings = []
            @outside  = []
            @heating  = []
            r = 18.0
            @size.times do |i|
                r = step(@start + (i * STEP), i, r, a)
            end
        end

        def step(time, index, r, a)
            outside = 5 + (5 * Math.sin(index * 2 * Math::PI / 144))
            on = index % 36 < 18
            record(time, r, outside, on)
            r + (a * (outside - r)) + (on ? 0.5 : 0) + noise
        end

        def record(time, r, outside, on)
            @readings << reading(time, "room", "ceil", r)
            @outside << reading(time, nil, "outside", outside)
            @heating << [time, nil, 1] if on
        end

        def noise = (@random.rand - 0.5) * 0.1

        def reading(time, location, device, value)
            Sensorium::Reading.new(time:, location:, device:, value:)
        end
    end
end
