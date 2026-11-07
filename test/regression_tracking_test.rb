# frozen_string_literal: true

require "test_helper"

# A Regression followed between two learnings (Regression#follow), as
# the Tracker follows an Offset: a value that keeps to the model stays
# ok; one that steps away jumps within days; a Regression learned again
# starts a fresh track. A made-up house whose gas a day is 5 kWh plus 2
# per unit of a, observed once a day.
class RegressionTrackingTest < Minitest::Test
    DAY = 86_400
    GAS = Sensorium::Quantity.new(name: "gas", unit: "kWh", sigma: 0.2,
                                  drift: 1.0, cusum_block: 3 * DAY)
    START = Time.utc(2024, 1, 1).to_i

    def setup
        @random = Random.new(1)
        setup = Sensorium::Setup.new(quantity: GAS, bin: DAY, joint: true,
                                     min_samples: 100, min_part: 20)
        @regression = Sensorium::Regression.learn(
            *history, setup, name: "house"
        ).first
    end

    def test_a_value_that_keeps_to_the_model_stays_ok
        track = follow(60)
        assert_equal :ok, track.state
        assert_operator track.delta.abs, :<, 0.5
    end

    # 3 kWh a day more from day 0: jumped within a week, nil foreseen.
    def test_a_step_is_a_jump
        days = (1..30).find { follow(it, step: 3.0).state == :jumped }
        assert_operator days, :<=, 7
        track = follow(days, step: 3.0)
        assert_nil @regression.predict({ "a" => 1.0 }, track:)
    end

    # Ok, its delta is put back in what is predicted.
    def test_the_track_moves_what_is_predicted
        track = follow(30, step: 0.3)
        plain = @regression.predict({ "a" => 1.0 })
        tracked = @regression.predict({ "a" => 1.0 }, track:)
        assert_equal :ok, track.state
        assert_in_delta plain.value + track.delta, tracked.value
        assert_operator tracked.sigma, :>, plain.sigma
    end

    def test_a_regression_learned_again_starts_a_fresh_track
        track = follow(30, step: 1.0)
        again = @regression.with(constant: @regression.constant + 1)
        fresh = again.follow(track, observed: 7.0, values: { "a" => 1.0 },
                                    at: Time.at(START + (1000 * DAY)),
                                    quantity: GAS)
        assert_in_delta 0.0, fresh.cusum_up
        assert_nil fresh.location
        assert_equal "house", fresh.device
    end

    private

    # [y, regressors] of 400 days.
    def history
        bins = (0...400).map { START + (it * DAY) }
        a = bins.to_h { [it, 10 * @random.rand] }
        [bins.to_h { [it, gas(a[it])] }, { "a" => a }]
    end

    def gas(a, step = 0.0) = 5 + (2 * a) + (@random.rand - 0.5) + step

    # The track after `days` days observed past the history, step more
    # each day than the model says.
    def follow(days, step: 0.0)
        random = Random.new(2)
        (1..days).reduce(nil) do |track, day|
            a = 10 * random.rand
            @regression.follow(track, observed: gas(a, step),
                                      values: { "a" => a },
                                      at: Time.at(START + ((400 + day) * DAY)),
                                      quantity: GAS)
        end
    end
end
