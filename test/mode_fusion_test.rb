# frozen_string_literal: true

require "test_helper"
require "support/fusion_helpers"

# A sensor under a Mode: corrected with the Shift of what holds, or
# with the plain offset alone when none was learned for it (a value
# never seen, or two Modes whose pair was not): what a Shift would add
# is not known, and the full model's terms were never seen under a
# Mode.
class ModeFusionTest < Minitest::Test
    include FusionHelpers

    BOTH = { "room" => { "aircon" => "cooling", "fan" => "on" } }.freeze

    # The aircon heating, a value no Shift was learned for: the plain
    # offset, not the full model (airzone's heating term), its σ the
    # plain one.
    def test_a_sensor_without_a_shift_for_the_mode_takes_the_plain_offset
        found = part(with_heating_term("heating"), "airzone").part
        assert_in_delta 21.5 - 1.2, found.value
        assert_in_delta 0.6 / Sensorium::P10_P90, found.sigma
    end

    # Two Modes holding, a Shift for each and one for the pair: the
    # pair's applies, not the sum of the two.
    def test_two_modes_holding_take_the_shift_of_the_pair
        fused = fuse({ "ceil" => 20.0, "airzone" => 26.0 },
                     shifts: [shift("aircon", "cooling"), shift("fan", "on"),
                              shift("aircon+fan", "cooling+on", 5.0)],
                     modes: BOTH)
        assert_in_delta 20.0, fused.value
    end

    # Two Modes holding, a Shift for each but none for the pair: neither
    # applies, nor their sum; the plain offset.
    def test_two_modes_without_a_shift_of_their_own_take_the_plain_offset
        fused = fuse({ "ceil" => 20.0, "airzone" => 21.0 },
                     shifts: [shift("aircon", "cooling"), shift("fan", "on")],
                     modes: BOTH)
        assert_in_delta 20.0, fused.value
    end

    private

    # Airzone with a heating term (0.5 over its constant 1.0; plain 1.2,
    # ±0.3), reading 21.5 with the heating on and the aircon at `mode`,
    # its only Shift the cooling's.
    def with_heating_term(mode)
        airzone = offset("airzone", 1.0, 0.1).with(
            switches: { "heating" => 0.5 }, plain: 1.2, plain_p10: -0.3,
            plain_p90: 0.3
        )
        fusion = Sensorium::Fusion.new(Sensorium::Presets.room,
                                       offsets: [offsets.first, airzone],
                                       shifts: [shift("aircon", "cooling")])
        snap = snapshot("room", { "airzone" => 21.5 },
                        { "room" => { "aircon" => mode } })
        fusion.location("room", snap.with(switches: { "heating" => Set[nil] }))
    end

    # Airzone's Shift under a Mode's value (or a pair's), in winter.
    def shift(influence, mode, by = 4.0)
        Sensorium::Shift.new(location: "room", device: "airzone",
                             quantity: "temperature", regime: "winter",
                             influence:, mode:, shift: by, p10: -0.1,
                             p90: 0.1, samples: 200)
    end
end
