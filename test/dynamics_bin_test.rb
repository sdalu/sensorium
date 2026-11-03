# frozen_string_literal: true

require "test_helper"

# Dynamics.learn with a bin that is whole seconds (Setup accepts it) but
# not a divisor of an hour: the same room, sampled at its bin, follows
# the same model; a bin of 400 s gets it, one of 480 s too, its horizon
# rounded to whole bins.
class DynamicsBinTest < Minitest::Test
    START = Time.utc(2026, 1, 5)
    DAYS  = 30

    # A room following dr = a (outside - r) + 0.05 per bin while heating,
    # with a little noise, a reading every bin.
    class Room
        def initialize(bin)
            @bin = bin
            @random = Random.new(7)
            @readings = []
            @outside = []
            @heating = []
            r = 18.0
            (DAYS * 86_400 / bin).times { r = record(it, r) }
        end

        def sensors(_quantity)
            [Sensorium::Sensor.new(name: "ceil", location: "room",
                                   tags: %w[ceiling])]
        end

        def readings(_q, from, to, _d) = within(@readings, from, to)
        def externals(_q, from, to) = within(@outside, from, to)

        def events(_name, from, to)
            @heating.select { (from..to).cover?(it.first) }
        end

        private

        # The room's value at the bin after index's.
        def record(index, r)
            seconds = index * @bin
            time = START + seconds
            outside = 5 + (5 * Math.sin(2 * Math::PI * seconds / 86_400.0))
            on = seconds % 21_600 < 10_800
            @readings << reading(time, "room", "ceil", r)
            @outside << reading(time, nil, "outside", outside)
            @heating << [time, nil, 1] if on
            stepped(r, outside, on)
        end

        def stepped(r, outside, on)
            r + (0.015 * (outside - r)) + (on ? 0.08 : 0) +
                ((@random.rand - 0.5) * 0.1)
        end

        def within(list, from, to) = list.select { (from..to).cover?(it.time) }

        def reading(time, location, device, value)
            Sensorium::Reading.new(time:, location:, device:, value:)
        end
    end

    def test_a_bin_dividing_an_hour_gets_a_model
        refute_empty learn(400)
    end

    def test_a_bin_not_dividing_an_hour_gets_a_model_too
        refute_empty learn(480)
    end

    # A bin longer than twice the horizon: the forecast is one bin
    # ahead, not none. c 0.1 a bin, the reference 0.5 up a bin later.
    def test_a_horizon_is_at_least_one_bin
        model = Sensorium::Dynamics::Model.new(
            location: "room", quantity: "temperature", regime: "winter",
            a: 0.0, c: 0.1, q: 0.0, bin: 9000, steps: 0
        )
        forecast = Sensorium::Dynamics::Forecast.new(
            { 0 => 20.0, 9000 => 20.5 }, nil, {}
        )
        found = forecast.errors(model, [0], 1.0)
                        .map { |pair| pair.map { it.round(9) } }
        assert_equal [[-0.4, -0.5]], found
    end

    private

    def learn(bin)
        heating = Sensorium::Influence::Switch.new(name: "heating", hold: 0)
        setup = Sensorium::Setup.new(quantity: Sensorium::Presets::TEMPERATURE,
                                     places: %w[ceiling], outside: "outside",
                                     influences: [heating], bin:)
        Sensorium::Dynamics.learn(Room.new(bin), setup,
                                  from: START, to: START + (DAYS * 86_400))
    end
end
