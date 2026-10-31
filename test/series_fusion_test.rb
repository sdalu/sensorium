# frozen_string_literal: true

require "test_helper"
require "support/fusion_helpers"

# A Series at fusion: its latest value within its hold; the plain offset
# when there is none. Learned on a made-up room whose "sunny" sensor
# reads 0.4 °C more per kW of the PV inverter.
class SeriesFusionTest < Minitest::Test
    include FusionHelpers

    SOLAR = Sensorium::Influence::Series.new(name: "solar", hold: 1800)
    SETUP = Sensorium::Setup.new(quantity: Sensorium::Presets::TEMPERATURE,
                                 places: %w[ceiling], influences: [SOLAR])

    def test_the_latest_value_within_the_hold
        snap = Sensorium::Snapshot.from(SunnyRoom.new, SETUP, at: AT)
        assert_equal({ nil => 2000.0 }, snap.feeds.fetch("solar"))
        assert_equal({ "solar" => 2000.0 }, snap.fed("room"))
    end

    def test_none_older_than_the_hold
        snap = Sensorium::Snapshot.from(SunnyRoom.new(age: 1801), SETUP,
                                        at: AT)
        assert_empty snap.fed("room")
    end

    # 0.4 × 2 kW over the ceiling.
    def test_a_sensor_corrected_for_the_sun
        assert_in_delta 0.0, sunny(SunnyRoom.new)
    end

    def test_without_the_suns_value_the_plain_offset
        assert_in_delta 0.8, sunny(SunnyRoom.new(age: 3600))
    end

    def test_a_sunny_sensor_is_learned_with_the_series
        room = SunnyRoom.new
        found = Sensorium::Learner.new(room, SETUP, from: room.start,
                                                    to: AT).learn.offsets
        assert_in_delta 4e-4, found.first.series.fetch("solar"), 1e-5
    end

    private

    # The sunny sensor, corrected, less the ceiling.
    def sunny(room)
        snap = Sensorium::Snapshot.from(room, SETUP, at: AT)
        fused = Sensorium::Fusion.new(SETUP, offsets:, shifts: [])
                                 .location("room", snap)
        part(fused, "sunny").part.value - part(fused, "ceil").part.value
    end

    def offsets
        [offset("sunny", 0.0, 0.1).with(reference: "ceil", regime: "all",
                                        series: { "solar" => 4e-4 })]
    end

    # Ten days to AT; the inverter's last event `age` before AT, 2 kW
    # then and at AT.
    class SunnyRoom
        AT = FusionHelpers::AT

        def initialize(age: 0) = @age = age

        def start = AT - (10 * 86_400)

        def sensors(_quantity)
            [Sensorium::Sensor.new(name: "ceil", location: "room",
                                   tags: %w[ceiling]),
             Sensorium::Sensor.new(name: "sunny", location: "room")]
        end

        def readings(_quantity, from, to, _devices)
            times.grep(from..to).flat_map do |time|
                r = 20 + Math.sin(time.to_i / 20_000.0)
                [read("ceil", time, r),
                 read("sunny", time, r + (4e-4 * solar(time)))]
            end
        end

        def events(_name, from, to)
            times.grep(from..(AT - @age)).grep(from..to)
                 .map { [it, nil, solar(it)] }
        end

        private

        def times = (0..1440).map { start + (it * 600) }

        def solar(time)
            return 2000.0 if [AT - @age, AT].include?(time)
            [3000 * Math.sin(time.to_i / 7000.0), 0].max
        end

        def read(device, time, value)
            Sensorium::Reading.new(time:, location: "room", device:, value:)
        end
    end
end
