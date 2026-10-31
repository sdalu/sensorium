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

    # A Prior's mean may be non-finite (nothing guards it): the fit it
    # pulls into is then refused, as a singular one is.
    def test_a_non_finite_fit_gives_no_model
        key = { location: "room", quantity: "temperature", regime: "winter" }
        found = Sensorium::Dynamics::Regression.model(
            key, nan_steps, nan_setup, nan_forecast, nan_prior
        )
        assert_nil found
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

    # Twenty steps of a Switch half on, half off, no outside.
    def nan_steps
        (0...20).map do |i|
            on = i.even? ? ["heating"] : []
            Sensorium::Dynamics::History::Step.new(
                bin: i * 600, gap: nil, on:,
                change: 0.1 + (on.empty? ? 0 : 0.5)
            )
        end
    end

    # A NaN mean, which Prior does not guard against (only σ).
    def nan_prior
        Sensorium::Dynamics::Prior.new(b: { "heating" => [Float::NAN, 0.01] })
    end

    def nan_setup
        heating = Sensorium::Influence::Switch.new(name: "heating", hold: 0)
        Sensorium::Setup.new(quantity: Sensorium::Presets::TEMPERATURE,
                             places: %w[ceiling], min_samples: 10,
                             influences: [heating])
    end

    def nan_forecast
        reference = (0..(26 * 600)).step(600).to_h { [it, 20.0] }
        Sensorium::Dynamics::Forecast.new(reference, {}, {})
    end
end
