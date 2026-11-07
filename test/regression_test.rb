# frozen_string_literal: true

require "timeout"

require "test_helper"

# A Regression: a quantity explained by regressors, per regime, its
# terms chosen and confirmed as an Offset's are. A made-up house whose
# gas a day is a base plus 0.03 kWh per valve-%-hour of two rooms,
# their valves open together but not alike.
class RegressionTest < Minitest::Test
    DAY = 86_400
    GAS = Sensorium::Quantity.new(name: "gas", unit: "kWh", sigma: 0.5,
                                  drift: 5.0, cusum_block: 7 * DAY)
    # Winter Nov–Mar, the rest summer.
    SEASONS = Sensorium::Regime::Calendar.new(
        { "winter" => [11, 12, 1, 2, 3], "summer" => [4, 5, 6, 7, 8, 9, 10] }
    )
    BINS = (0...730).map { Time.utc(2024, 1, 1).to_i + (it * DAY) }.freeze

    def setup
        @random = Random.new(5)
        @a = drawn { |x, _| 400 * x }
        @b = drawn { |x, bin| (0.8 * @a[bin]) + (100 * x) }
        @noise = drawn { |x, _| x - 0.5 }
    end

    def test_the_terms_found_together
        found = learn(&method(:both)).first
        assert_in_delta 12.0, found.constant, 0.3
        assert_in_delta 0.03, found.terms.fetch("a"), 0.002
        assert_in_delta 0.03, found.terms.fetch("b"), 0.002
        assert_operator found.sigma, :<, 0.5
    end

    # Each in turn, the first given takes the other's share, and the
    # other is left out: the order they were given in decides. Fitted
    # together, it does not.
    def test_each_in_turn_the_order_decides
        assert_equal %w[a], terms(joint: false).keys
        assert_equal %w[b], terms(joint: false, order: %w[b a]).keys
        assert_equal terms, terms(order: %w[b a])
    end

    def test_a_regressor_that_explains_nothing_is_left_out
        c = drawn { |x, _| 400 * x }
        found = learn(c:) { |bin| 12 + (0.03 * @a[bin]) }.first
        assert_equal %w[a], found.terms.keys
    end

    def test_one_per_regime_in_its_order
        found = learn(regime: SEASONS) do |bin|
            winter = SEASONS.of(Time.at(bin)) == "winter"
            (winter ? 12 : 5) + (0.03 * @a[bin])
        end
        assert_equal %w[winter summer], found.map(&:regime)
        assert_in_delta 12.0, found.first.constant, 0.5
        assert_in_delta 5.0, found.last.constant, 0.5
    end

    def test_a_regime_short_of_samples_is_not_learned
        assert_empty learn(min_samples: 1000) { 12 }
    end

    def test_each_regressors_share
        values = { "a" => 100.0, "b" => 200.0 }
        shares = learn(&method(:both)).first.contributions(values)
        assert_in_delta 3.0, shares.fetch("a"), 0.3
        assert_in_delta 6.0, shares.fetch("b"), 0.5
    end

    def test_a_prediction_is_the_constant_and_the_shares
        found = learn(&method(:both)).first
        values = { "a" => 100.0, "b" => 200.0 }
        predicted = found.predict(values)
        assert_in_delta found.constant + found.contributions(values)
                                              .values.sum, predicted.value
        assert_in_delta found.sigma, predicted.sigma
    end

    # A regressor's value unknown: the plain median, with its own σ.
    def test_without_a_value_the_plain_median
        found = learn { |bin| 12 + (0.03 * @a[bin]) }.first
        predicted = found.predict({ "a" => nil })
        assert_in_delta found.plain, predicted.value
        assert_in_delta found.plain_sigma, predicted.sigma
        assert_operator found.plain_sigma, :>, found.sigma
    end

    # A Symbol is the same name as its String (DESIGN.md, Names are
    # Strings): not an unknown value, and not a missing one.
    def test_symbol_names_are_the_same_regressors
        found = learn { |bin| 12 + (0.03 * @a[bin]) }.first
        assert_equal found.predict({ "a" => 100.0 }),
                     found.predict({ a: 100.0 })
        assert_equal found.contributions({ "a" => 100.0 }),
                     found.contributions({ a: 100.0 })
    end

    # Fitted together, a slope held at 0 is no term: the choice ends
    # rather than keep the same model again, whatever narrows allows.
    def test_a_slope_held_at_zero_ends_the_choice
        found = Timeout.timeout(10) do
            learn(nonnegative: true, narrows: 1.0) do |bin|
                12 + (0.03 * @a[bin]) - (0.01 * @b[bin])
            end
        end
        assert_equal %w[a], found.first.terms.keys
    end

    private

    # { bin => the block's of a draw in 0..1, and the bin }.
    def drawn
        BINS.to_h { [it, yield(@random.rand, it)] }
    end

    # The gas of both rooms' valves, noise aside.
    def both(bin) = 12 + (0.03 * (@a[bin] + @b[bin]))

    # The terms of the first Regression of both rooms.
    def terms(**) = learn(**, &method(:both)).first.terms

    # The Regressions of y = the block's + noise on a and b (and c);
    # order: the regressors' names in the order they are given.
    def learn(joint: true, c: nil, order: %w[a b], **settings)
        setup = Sensorium::Setup.new(quantity: GAS, bin: DAY, joint:,
                                     min_samples: 100, min_part: 30,
                                     **settings)
        y = BINS.to_h { [it, yield(it) + @noise[it]] }
        regressors = { "a" => @a, "b" => @b, "c" => c }.compact
        Sensorium::Regression.learn(y, regressors.slice(*order)
                                                 .merge(regressors),
                                    setup, name: "house")
    end
end
