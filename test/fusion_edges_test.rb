# frozen_string_literal: true

require "test_helper"
require "support/fusion_helpers"

# Fusion at its edges (FusionHelpers' room): the regime's own reference,
# a zero spread, whole-number readings, a neighbour too old.
class FusionEdgesTest < Minitest::Test
    include FusionHelpers

    JULY = Time.utc(2026, 7, 10, 12)

    # Winter learned against the ceiling, summer against the floor.
    def test_the_reference_is_the_moments_regimes
        winter = offset("tado", -1.0, 0.25)
        summer = offset("tado", -0.5, 0.25).with(regime: "summer",
                                                 reference: "leak")
        fusion = Sensorium::Fusion.new(Sensorium::Presets.room,
                                       offsets: [winter, summer], shifts: [])
        fused = fusion.location("room", july("leak" => 25.0, "tado" => 24.5))
        assert_equal "leak", fused.reference
        assert_in_delta 25.0, fused.value
    end

    # A sensor learned with no spread at all, read at age 0.
    def test_a_zero_width_offset_does_not_take_over
        zero = [offset("tado", -1.0, 0.0), offset("airzone", 1.0, 0.0)]
        fusion = Sensorium::Fusion.new(Sensorium::Presets.room,
                                       offsets: zero, shifts: [])
        readings = { "ceil" => 20.0, "tado" => 19.4, "airzone" => 21.0 }
        fused = fusion.location("room", snapshot("room", readings))
        assert fused.value.finite?
        assert_operator weight(fused, "ceil"), :>, 0.05
    end

    def test_whole_number_readings_have_a_fractional_mean
        fused = fuse({ "a" => 401, "b" => 402 }, location: "blue")
        assert_in_delta 401.5, fused.value
    end

    # Learned against the garage, whose reading is three hours old.
    def test_a_neighbour_too_old_falls_back_to_plain
        tado = offset("tado", -1.0, 0.1).with(neighbour: "garage/g1",
                                              coefficient: -0.3, plain: -2.0)
        fusion = Sensorium::Fusion.new(Sensorium::Presets.room,
                                       offsets: [tado], shifts: [])
        fused = fusion.location("room", with_old_garage)
        assert_in_delta 20.0, part(fused, "tado").part.value
    end

    # A misspelt option would silently fuse without what it names.
    def test_an_unknown_option_is_refused
        assert_raises(ArgumentError) do
            Sensorium::Fusion.new(Sensorium::Presets.room,
                                  offsets: [], shifts: [], track: {})
        end
    end

    private

    def with_old_garage
        snap = snapshot("room", { "tado" => 18.0 })
        old = Sensorium::Reading.new(time: AT - (3 * 3600), location: "garage",
                                     device: "g1", value: 10.0)
        snap.with(latest: snap.latest.merge(%w[garage g1] => old))
    end

    def july(readings)
        latest = readings.to_h do |device, value|
            [["room", device],
             Sensorium::Reading.new(time: JULY, location: "room", device:,
                                    value:)]
        end
        Sensorium::Snapshot.new(at: JULY, latest:)
    end
end
