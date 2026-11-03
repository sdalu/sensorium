# frozen_string_literal: true

require "test_helper"

# When a location's dynamics give no model: one that beats holding the
# last value by less than the setup's margin, one whose fit is not
# finite.
class DynamicsGuardsTest < Minitest::Test
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
