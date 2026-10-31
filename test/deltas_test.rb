# frozen_string_literal: true

require "test_helper"
require "support/fusion_helpers"

# Send-on-delta (FusionHelpers' room): a device that reports only when
# its value moved by its delta is within the delta of the truth while it
# is alive, so its age adds at most delta² / 3 to σ².
class DeltasTest < Minitest::Test
    include FusionHelpers

    # 50 minutes old: drift 1 °C/h gives 0.83², the delta 0.2²/3.
    def test_the_age_term_is_capped_by_the_delta
        sigma = ceil_sigma(deltas: { "ceil" => 0.2 })
        assert_in_delta Math.sqrt((0.1**2) + (0.04 / 3)), sigma
    end

    def test_a_wide_delta_leaves_the_age_term
        sigma = ceil_sigma(deltas: { "ceil" => 5.0 })
        assert_in_delta Math.hypot(0.1, 50 / 60.0), sigma
    end

    def test_a_device_without_a_delta_is_not_capped
        sigma = ceil_sigma(deltas: { "tado" => 0.2 })
        assert_in_delta Math.hypot(0.1, 50 / 60.0), sigma
    end

    def test_the_cap_holds_over_the_models_variance
        fused = with_model(deltas: { "ceil" => 0.2 })
        assert_in_delta Math.sqrt((0.1**2) + (0.04 / 3)),
                        part(fused, "ceil").part.sigma
        assert_in_delta 20.0 + (0.01 * 5), fused.value
    end

    def test_a_reading_older_than_max_age_still_does_not_count
        fused = fuse({ "ceil" => [20.0, 3700], "tado" => [19.0, 0] },
                     locations: room(deltas: { "ceil" => 0.2 }))
        assert_equal "stale", note(fused, "ceil")
    end

    # The delta is in %RH; σ is in g/m³, at the reading's temperature.
    def test_a_delta_is_taken_into_the_transforms_space
        setup = Sensorium::Presets.room(Sensorium::Presets::HUMIDITY)
        wall = { "wall" => [50.0, 3000, { temperature: 20.0 }] }
        fused = fuse(wall, setup:, context: { temperature: 20.0 },
                           locations: room(references: %w[wall],
                                           deltas: { "wall" => 2.0 }))
        inside = 2.0 * Sensorium::Transform::AbsoluteHumidity
                 .saturation(20.0) / 100
        assert_in_delta Math.sqrt((0.3**2) + ((inside**2) / 3)),
                        part(fused, "wall").part.sigma
    end

    private

    def ceil_sigma(deltas:)
        fused = fuse({ "ceil" => [20.0, 3000] }, locations: room(deltas:))
        part(fused, "ceil").part.sigma
    end

    def room(**settings)
        { "room" => Sensorium::Location.new(name: "room", **settings) }
    end

    def with_model(deltas:)
        model = Sensorium::Dynamics::Model.new(
            location: "room", quantity: "temperature", regime: "winter",
            a: 0.0, b: {}, c: 0.01, q: 0.04, bin: 600, steps: 1000
        )
        Sensorium::Fusion.new(Sensorium::Presets.room, offsets:, shifts: [],
                                                       locations: room(deltas:),
                                                       dynamics: [model])
                         .location("room",
                                   snapshot("room", { "ceil" => [20.0, 3000] }))
    end
end
