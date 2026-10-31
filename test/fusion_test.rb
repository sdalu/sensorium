# frozen_string_literal: true

require "test_helper"
require "support/fusion_helpers"

# Fusion: a room's sensors corrected to its reference and weighted by
# 1/σ² (FusionHelpers' room).
class FusionTest < Minitest::Test
    include FusionHelpers

    def test_the_sensors_agree_and_the_tightest_counts_most
        fused = fuse({ "ceil" => 20.0, "tado" => 19.0, "airzone" => 21.0 })
        assert_in_delta 20.0, fused.value
        assert_operator fused.sigma, :<, 0.07
        assert_in_delta 1.0, fused.parts.sum(&:weight)
        assert_equal "airzone", fused.parts.max_by(&:weight).part.device
        assert_in_delta 20.0, part(fused, "tado").value
    end

    def test_an_old_reading_counts_less_and_a_stale_one_not
        fused = fuse({ "ceil" => [20.2, 1800], "tado" => 19.0,
                       "airzone" => 21.0 })
        assert_nil note(fused, "ceil")
        assert_operator weight(fused, "ceil"), :<, 0.05
        assert_in_delta 20.0, fused.value, 0.05
        fused = fuse({ "ceil" => [25.0, 7200], "airzone" => 21.0 })
        assert_equal "stale", note(fused, "ceil")
        assert_in_delta 20.0, fused.value
    end

    # Sun on tado: 6 °C off. Its Student-t factor falls below the
    # outlier threshold (noted, but it still carries a little weight),
    # and the fused value barely moves.
    def test_an_outlier_is_dropped
        fused = fuse({ "ceil" => 20.0, "tado" => 25.0, "airzone" => 21.0 })
        assert_equal "outlier", note(fused, "tado")
        assert_in_delta 20.0, fused.value, 0.01
    end

    def test_excluded_and_not_learned_do_not_count
        locations = { "room" => Sensorium::Location.new(name: "room",
                                                        exclude: %w[tado]) }
        fused = fuse({ "ceil" => 20.0, "tado" => 19.0, "branch" => 30.0 },
                     locations:)
        assert_equal "excluded", note(fused, "tado")
        assert_equal "not learned", note(fused, "branch")
        assert_in_delta 20.0, fused.value
    end

    # Learned in summer only, so not learned in January.
    def test_the_offsets_are_the_regimes
        summer = offsets.map { it.with(regime: "summer") }
        fusion = Sensorium::Fusion.new(Sensorium::Presets.room,
                                       offsets: summer, shifts: [])
        fused = fusion.location("room", snapshot("room", { "ceil" => 20.0,
                                                           "tado" => 19.0 }))
        assert_equal "not learned", note(fused, "tado")
        assert_equal "ceil", fused.reference
    end

    def test_a_location_without_reference_is_the_plain_mean
        fused = fuse({ "tado" => 20.0, "airzone" => 21.0 }, location: "blue")
        assert_in_delta 20.5, fused.value
        assert_nil fused.sigma
        refute fused.corrected
    end

    def test_the_aircon_shift_is_applied_while_it_runs
        shift = Sensorium::Shift.new(location: "room", device: "airzone",
                                     quantity: "temperature",
                                     regime: "winter", influence: "aircon",
                                     mode: "cooling", shift: 4.0, p10: -0.1,
                                     p90: 0.1, samples: 200)
        fused = fuse({ "ceil" => 20.0, "airzone" => 25.0 },
                     shifts: [shift],
                     modes: { "room" => { "aircon" => "cooling" } })
        assert_in_delta 20.0, fused.value
    end

    def test_the_locations_it_can_tell
        fusion = Sensorium::Fusion.new(Sensorium::Presets.room,
                                       offsets:, shifts: [])
        snap = snapshot("attic", { "batman" => 11.0 })
        assert_equal %w[attic room], fusion.locations(snap)
    end
end
