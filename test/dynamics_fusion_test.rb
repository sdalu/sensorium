# frozen_string_literal: true

require "test_helper"
require "support/fusion_helpers"

# An aged reading at fusion, with a Dynamics::Model of its location
# (FusionHelpers' room, in winter): moved by the change the model
# predicts over its age, its σ² grown by q × age; without a model, or
# without the outside it needs, by the quantity's drift.
class DynamicsFusionTest < Minitest::Test
    include FusionHelpers

    # Half an hour old (three bins), the outside at 10: 20 moves as the
    # model stepped three bins, r += 0.1 × (10 - r) + 0.01.
    def test_an_aged_reading_moves_toward_the_prediction
        fused = aged({ "ceil" => [20.0, 1800] })
        assert_in_delta 17.3171, part(fused, "ceil").part.value
        assert_in_delta 17.3171, fused.value
    end

    def test_its_variance_grows_by_q_times_its_age
        fused = aged({ "ceil" => [20.0, 1800] })
        assert_in_delta Math.sqrt((0.1**2) + (0.04 * 0.5)),
                        part(fused, "ceil").part.sigma
    end

    def test_a_switch_on_adds_its_term
        fused = aged({ "ceil" => [20.0, 1800] }, on: true)
        assert_in_delta 18.6721, part(fused, "ceil").part.value
    end

    # tado reads 1 low (σ 0.25 × 2 / 2.563): corrected, then moved.
    def test_a_corrected_reading_is_moved_too
        tado = part(aged({ "tado" => [19.0, 1800] }), "tado").part
        sigma = 0.5 / Sensorium::P10_P90
        assert_in_delta 17.3171, tado.value
        assert_in_delta Math.sqrt((sigma**2) + 0.02), tado.sigma
    end

    def test_a_fresh_reading_does_not_move
        fused = aged({ "ceil" => [20.0, 0] })
        assert_in_delta 20.0, fused.value
        assert_in_delta 0.1, part(fused, "ceil").part.sigma
    end

    def test_without_the_outside_the_drift_rule
        fused = aged({ "ceil" => [20.0, 1800] }, outside: nil)
        assert_in_delta 20.0, fused.value
        assert_in_delta Math.hypot(0.1, 0.5), part(fused, "ceil").part.sigma
    end

    # The outside read 70 minutes ago, past the location's max_age.
    def test_an_outside_older_than_max_age_is_not_known
        fused = aged({ "ceil" => [20.0, 1800] }, outside: 10.0,
                                                 outside_age: 4200)
        assert_in_delta 20.0, fused.value
        assert_in_delta Math.hypot(0.1, 0.5), part(fused, "ceil").part.sigma
    end

    def test_an_outside_within_max_age_counts
        fused = aged({ "ceil" => [20.0, 1800] }, outside: 10.0,
                                                 outside_age: 3600)
        assert_in_delta 17.3171, fused.value
    end

    def test_a_model_without_an_outside_term_needs_none
        fused = aged({ "ceil" => [20.0, 1800] }, outside: nil,
                                                 model: model.with(a: 0.0))
        assert_in_delta 20.03, fused.value
    end

    def test_a_model_of_another_regime_is_not_used
        fused = aged({ "ceil" => [20.0, 1800] },
                     model: model.with(regime: "summer"))
        assert_in_delta 20.0, fused.value
        assert_in_delta Math.hypot(0.1, 0.5), part(fused, "ceil").part.sigma
    end

    def test_a_reading_older_than_max_age_still_does_not_count
        fused = aged({ "ceil" => [20.0, 3700], "tado" => [19.0, 0] })
        assert_equal "stale", note(fused, "ceil")
    end

    private

    def aged(readings, outside: 10.0, outside_age: 0, on: false,
             model: self.model)
        snap = snapshot("room", readings)
        snap = with_outside(snap, outside, outside_age) if outside
        snap = snap.with(switches: { "heating" => Set[nil] }) if on
        Sensorium::Fusion.new(setup, offsets:, shifts: [], dynamics: [model])
                         .location("room", snap)
    end

    def with_outside(snap, value, age)
        reading = Sensorium::Reading.new(time: AT - age, location: nil,
                                         device: "outside", value:)
        snap.with(latest: snap.latest.merge([nil, "outside"] => reading))
    end

    def setup = Sensorium::Presets.room.with(outside: "outside")

    def model
        Sensorium::Dynamics::Model.new(location: "room",
                                       quantity: "temperature",
                                       regime: "winter", a: 0.1,
                                       b: { "heating" => 0.5 }, c: 0.01,
                                       q: 0.04, bin: 600, steps: 1000)
    end
end
