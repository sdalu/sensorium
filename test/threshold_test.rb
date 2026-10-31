# frozen_string_literal: true

require "test_helper"
require "support/fusion_helpers"

# Humidity creep: a sensor reads high for hours after its location's
# reference was above 80 % (a shower). A made-up bathroom showered an
# hour a day; its "damp" sensor reads 3 % over the wall unit for six
# hours after, both at 20 °C.
class ThresholdTest < Minitest::Test
    include FusionHelpers

    HUMIDITY = Sensorium::Presets::HUMIDITY
    SETUP    = Sensorium::Presets.room(HUMIDITY)
    AH       = Sensorium::Transform::AbsoluteHumidity
    CREEP    = 3 * AH.saturation(20.0) / 100

    def test_the_humidity_preset_creeps_above_80_for_six_hours
        assert_equal 1, SETUP.thresholds.size
        creep = SETUP.thresholds.first
        assert_equal ["creep", 80, 6 * 3600],
                     [creep.name, creep.above, creep.hold]
        assert_empty Sensorium::Presets.room.thresholds
    end

    # Learned as a Switch, on the reference as it reads (in g/m³ it is
    # never above 80).
    def test_a_damp_sensor_learns_the_creep
        damp = learned(Bathroom.new).offsets.find { it.device == "damp" }
        assert_in_delta CREEP, damp.switches.fetch("creep"), 0.02
    end

    def test_a_sensor_that_does_not_creep_learns_none
        damp = learned(Bathroom.new(creep: 0)).offsets
                                              .find { it.device == "damp" }
        assert_empty damp.switches
    end

    def test_at_fusion_the_creep_holds_six_hours
        assert_in_delta CREEP, creep_at(5)
        assert_in_delta 0.0, creep_at(7)
    end

    private

    def learned(room)
        Sensorium::Learner.new(room, SETUP, from: room.start, to: AT).learn
    end

    # What the damp sensor is corrected by, the last shower ending `ago`
    # hours before AT.
    def creep_at(ago)
        room = Bathroom.new(showers: [AT - ((ago + 1) * 3600)])
        snap = Sensorium::Snapshot.from(room, SETUP, at: AT)
        fused = fusion(setup: SETUP).location("bath", snap,
                                              context: { temperature: 20.0 })
        damp = part(fused, "damp").part
        AH.forward(damp.raw, temperature: 20.0) - damp.value
    end

    def offsets
        [offset("damp", 0.0, 0.1, quantity: "humidity")
            .with(location: "bath", reference: "wall-ref",
                  switches: { "creep" => CREEP })]
    end

    # Ten days to AT at 20 °C; the wall unit at 60 %, 85 % during each
    # hour-long shower (daily at midnight unless given); the damp sensor
    # `creep` % over it from a shower's start to six hours after its end.
    class Bathroom
        AT = FusionHelpers::AT

        def initialize(showers: nil, creep: 3)
            @showers = showers || (1..10).map { AT - (it * 86_400) - 43_200 }
            @creep = creep
        end

        def start = AT - (10 * 86_400)

        def sensors(_quantity)
            [Sensorium::Sensor.new(name: "wall-ref", location: "bath",
                                   tags: %w[wall]),
             Sensorium::Sensor.new(name: "damp", location: "bath")]
        end

        def readings(_quantity, from, to, _devices)
            times.grep(from..to).flat_map do |time|
                wall = shower?(time) ? 85.0 : 60.0
                [read("wall-ref", time, wall),
                 read("damp", time, wall + (creep?(time) ? @creep : 0))]
            end
        end

        private

        def times = (0..1440).map { start + (it * 600) }

        def shower?(time) = @showers.any? { (it...(it + 3600)).cover?(time) }

        def creep?(time)
            @showers.any? { (it..(it + (7 * 3600) - 600)).cover?(time) }
        end

        def read(device, time, value)
            Sensorium::Reading.new(time:, location: "bath", device:, value:,
                                   context: { temperature: 20.0 })
        end
    end
end
