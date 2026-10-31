# frozen_string_literal: true

require "test_helper"
require "support/fusion_helpers"

# A filtered Switch learned and fused: a made-up room whose "warm"
# sensor reads 1 °C over its ceiling at full exposure to the radiators'
# water (tau one hour), the valves open three hours in six.
class FilteredFusionTest < Minitest::Test
    include FusionHelpers

    HEATING = Sensorium::Influence::Switch.new(
        name: "heating", hold: 0, tau: Sensorium::Influence::TAUS
    )
    SETUP = Sensorium::Setup.new(quantity: Sensorium::Presets::TEMPERATURE,
                                 places: %w[ceiling], influences: [HEATING])

    def test_a_warm_sensor_is_learned_with_its_time_constant
        warm = learned.offsets.first
        assert_equal({ "heating" => 3600 }, warm.taus)
        assert_in_delta 1.0, warm.switches.fetch("heating"), 0.03
    end

    # A hard Switch learns no time constant.
    def test_a_hard_switch_has_none
        hard = SETUP.with(influences: [HEATING.with(tau: nil)])
        assert_empty learned(hard).offsets.first.taus
    end

    # The exposure from the events of the last 5 tau: on two hours ago
    # for an hour (7 bins), off since (6 bins).
    def test_the_exposure_at_fusion
        keep = Math.exp(-600.0 / 1800)
        exposure = (1 - (keep**7)) * (keep**6)
        assert_in_delta exposure, warm(WarmRoom.new(last: AT - 7200))
    end

    private

    def learned(setup = SETUP)
        room = WarmRoom.new
        Sensorium::Learner.new(room, setup, from: room.start, to: AT).learn
    end

    # The exposure the warm sensor was corrected for (term 1.0, tau
    # 1800): what it read less what it says.
    def warm(room)
        snap = Sensorium::Snapshot.from(room, SETUP.with(influences:
            [HEATING.with(hold: 3600, tau: 1800)]), at: AT)
        offset = offset("warm", 0.0, 0.1).with(
            reference: "ceil", regime: "all", switches: { "heating" => 1.0 },
            taus: { "heating" => 1800 }
        )
        fused = Sensorium::Fusion.new(SETUP, offsets: [offset], shifts: [])
                                 .location("room", snap)
        warm = part(fused, "warm").part
        warm.raw - warm.value
    end

    # Ten days to AT, the valves opened every ten minutes three hours in
    # six (the last at `last`, when given), the warm sensor at the
    # valves' exposure.
    class WarmRoom
        AT = FusionHelpers::AT

        def initialize(last: nil)
            @last = last
            @exposures = Sensorium::Series.new(600)
                                          .filtered(open.to_set(&:to_i),
                                                    start, AT, 3600)
        end

        def start = AT - (10 * 86_400)

        def sensors(_quantity)
            [Sensorium::Sensor.new(name: "ceil", location: "room",
                                   tags: %w[ceiling]),
             Sensorium::Sensor.new(name: "warm", location: "room")]
        end

        def readings(_quantity, from, to, _devices)
            times.grep(from..to).flat_map do |time|
                r = 20 + Math.sin(time.to_i / 20_000.0)
                [read("ceil", time, r),
                 read("warm", time, r + @exposures[time.to_i])]
            end
        end

        def events(_name, from, to)
            open.grep(from..to).map { [it, nil, 1] }
        end

        private

        def open
            return [@last] if @last
            times.select { (it.to_i / 10_800).even? }
        end

        def times = (0..1440).map { start + (it * 600) }

        def read(device, time, value)
            Sensorium::Reading.new(time:, location: "room", device:, value:)
        end
    end
end
