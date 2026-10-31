# frozen_string_literal: true

require "test_helper"
require "support/fusion_helpers"

# When a location's dynamics are not used: while a Mode holds (the
# model was fitted without those bins), and when it beats holding the
# last value by less than the setup's margin.
class DynamicsGuardsTest < Minitest::Test
    include FusionHelpers

    # The aircon cooling: the drift rule, as without a model.
    def test_no_model_while_a_mode_holds
        snap = snapshot("room", { "ceil" => [20.0, 1800] },
                        { "room" => { "aircon" => "cooling" } })
        outside = Sensorium::Reading.new(time: AT, location: nil,
                                         device: "outside", value: 10.0)
        snap = snap.with(latest: snap.latest.merge([nil, "outside"] => outside))
        fused = fusion.location("room", snap)
        assert_in_delta 20.0, fused.value
        assert_in_delta Math.hypot(0.1, 0.5), part(fused, "ceil").part.sigma
    end

    def test_a_model_must_win_by_the_margin
        setup = Sensorium::Presets.room
        validation = Sensorium::Dynamics::Validation
        assert validation.wins?([0.97, 1.0], setup)
        refute validation.wins?([0.99, 1.0], setup)
        refute validation.wins?([0.99, 1.0], setup.with(dynamics_margin: 0.98))
        assert validation.wins?([0.99, 1.0], setup.with(dynamics_margin: 1.0))
    end

    private

    def fusion
        setup = Sensorium::Presets.room.with(outside: "outside")
        Sensorium::Fusion.new(setup, offsets:, shifts: [], dynamics: [model])
    end

    def model
        Sensorium::Dynamics::Model.new(location: "room",
                                       quantity: "temperature",
                                       regime: "winter", a: 0.1,
                                       b: {}, c: 0.01, q: 0.04, bin: 600,
                                       steps: 1000)
    end
end
