# frozen_string_literal: true

require "test_helper"

# Two Modes at one location, the aircon ("cooling") and a fan ("on"),
# holding together part of the time: each Shift is learned over the
# bins its Mode held alone, and the two together are a value of their
# own, with a Shift over the bins both held. The sensor s reads 0.5
# above the reference when calm, 3.5 above under the aircon alone, 1.5
# under the fan alone and 5 under both: what the two do together is not
# the sum of what each does alone.
class TwoModesTest < Minitest::Test
    START = Time.utc(2026, 1, 5)
    STEP  = 600
    SIZE  = 10 * 144

    class Source
        # aircon, fan: the ranges of bins each holds over.
        def initialize(aircon, fan)
            @aircon = aircon
            @fan = fan
            @readings = []
            @events = Hash.new { |hash, key| hash[key] = [] }
            SIZE.times { record(it) }
        end

        def sensors(_quantity)
            [Sensorium::Sensor.new(name: "ceil", location: "room",
                                   tags: %w[ceiling]),
             Sensorium::Sensor.new(name: "s", location: "room")]
        end

        def readings(_quantity, from, to, _devices = nil)
            @readings.select { (from..to).cover?(it.time) }
        end

        def events(name, from, to)
            @events[name].select { (from..to).cover?(it.first) }
        end

        private

        def record(index)
            time = START + (index * STEP)
            noise = ((index * 7919) % 11) / 100.0
            @readings << reading(time, "ceil", 20.0)
            @readings << reading(time, "s", 20.0 + above(index) + noise)
            held(index).each do |name, value|
                @events[name] << [time, "room", value]
            end
        end

        # { influence => value } of the Modes holding at a bin.
        def held(index)
            { "aircon" => ("cooling" if @aircon.cover?(index)),
              "fan" => ("on" if @fan.cover?(index)) }.compact
        end

        # How far above the reference s reads at a bin.
        def above(index)
            case held(index).keys
            when %w[aircon fan] then 5.0
            when %w[aircon] then 3.5
            when %w[fan] then 1.5
            else 0.5
            end
        end

        def reading(time, device, value)
            Sensorium::Reading.new(time:, location: "room", device:, value:)
        end
    end

    def setup
        @setup = Sensorium::Setup.new(
            quantity: Sensorium::Presets::TEMPERATURE,
            influences: [Sensorium::Influence::Mode.new(name: "aircon"),
                         Sensorium::Influence::Mode.new(name: "fan")],
            places: %w[ceiling], gain: false, rate: false
        )
    end

    # The aircon over bins 300...600, the fan over 450...750: each
    # Shift is what its Mode alone does over the plain offset, over the
    # 150 bins it held alone.
    def test_a_shift_is_learned_over_the_bins_its_mode_held_alone
        shifts = learn(300...600, 450...750)
        aircon = shifts.fetch(%w[aircon cooling])
        assert_in_delta 3.0, aircon.shift, 0.1
        assert_equal 150, aircon.samples
        assert_in_delta 1.0, shifts.fetch(%w[fan on]).shift, 0.1
    end

    # The 150 bins both held are the pair's: its own Shift, not a sum.
    def test_two_modes_together_are_a_shift_of_their_own
        pair = learn(300...600, 450...750).fetch(%w[aircon+fan cooling+on])
        assert_in_delta 4.5, pair.shift, 0.1
        assert_in_delta 150, pair.samples, 3
    end

    # Always together: nothing says what either does alone.
    def test_two_modes_always_together_learn_only_the_pair
        shifts = learn(300...500, 300...500)
        assert_equal [%w[aircon+fan cooling+on]], shifts.keys
        assert_in_delta 4.5, shifts.values.first.shift, 0.1
    end

    # One Mode is named as it is; several in their names' order,
    # whatever order they hold in.
    def test_what_holds_is_named_in_the_modes_order
        assert_equal %w[aircon cooling],
                     Sensorium::Shift.named([%w[aircon cooling]])
        assert_equal %w[aircon+fan cooling+on],
                     Sensorium::Shift.named([%w[fan on], %w[aircon cooling]])
    end

    private

    # { [influence, value] => Shift } of s, learned over the source.
    def learn(aircon, fan)
        learned = Sensorium::Learner.new(Source.new(aircon, fan), @setup,
                                         from: START,
                                         to: START + (SIZE * STEP)).learn
        learned.shifts.select { it.device == "s" }
               .to_h { [[it.influence, it.mode], it] }
    end
end
