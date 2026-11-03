# frozen_string_literal: true

require "test_helper"

# A Mode reported every half hour (its hold): the aircon runs for 45 h
# straight, reported every 1800 s, s reading 5 above the reference
# meanwhile instead of 0.5. Each report holds for the Mode's hold, as
# the bins left out of the offset (Timeline#near?) and the Fusion have
# it: the Shift is learned over the 270 bins under the Mode, not only
# the 90 holding a report (fewer than min_shift), and the Fusion
# corrects by it.
class ModeCadenceTest < Minitest::Test
    START = Time.utc(2026, 1, 5)
    STEP  = 600
    SIZE  = 10 * 144
    COOL  = (300...570)

    class Source
        def initialize
            @readings = []
            @events = []
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
            return [] unless name == "aircon"
            @events.select { (from..to).cover?(it.first) }
        end

        private

        def record(index)
            time = START + (index * STEP)
            noise = ((index * 7919) % 11) / 100.0
            cooling = COOL.cover?(index)
            @readings << reading(time, "ceil", 20.0)
            @readings << reading(time, "s", 20.0 + (cooling ? 5.0 : 0.5) +
                                            noise)
            @events << [time, "room", "cooling"] if cooling && (index % 3).zero?
        end

        def reading(time, device, value)
            Sensorium::Reading.new(time:, location: "room", device:, value:)
        end
    end

    def setup
        @source = Source.new
        @setup  = Sensorium::Setup.new(
            quantity: Sensorium::Presets::TEMPERATURE,
            influences: [Sensorium::Influence::Mode.new(name: "aircon")],
            places: %w[ceiling], gain: false, rate: false
        )
        @learned = Sensorium::Learner.new(@source, @setup,
                                          from: START,
                                          to: START + (SIZE * STEP)).learn
    end

    def test_a_mode_held_270_bins_is_learned_as_a_shift
        shift = @learned.shifts.find { it.device == "s" }
        refute_nil shift, "no Shift for a Mode that held 270 bins"
        assert_in_delta 4.5, shift.shift, 0.1
    end

    def test_a_reading_under_the_mode_is_corrected_back_to_the_reference
        at = START + (400 * STEP) + 60
        snapshot = Sensorium::Snapshot.from(@source, @setup, at:)
        fused = Sensorium::Fusion.new(@setup, offsets: @learned.offsets,
                                              shifts: @learned.shifts)
                                 .location("room", snapshot)
        part = fused.parts.find { it.part.device == "s" }.part
        assert_in_delta 20.0, part.value, 0.2
    end
end
