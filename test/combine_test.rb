# frozen_string_literal: true

require "test_helper"

# Combine: the arithmetic Fusion applies to Parts::Part.
class CombineTest < Minitest::Test
    def test_two_wrong_together_pull_less_than_plain_weighted
        good = [part("a", 20.0, 0.1), part("b", 20.0, 0.1)]
        bad = [part("c", 23.0, 0.2), part("d", 23.0, 0.2)]
        value, = Sensorium::Combine.robust(good + bad, 4.0)
        plain, = Sensorium::Combine.weighted(good + bad)
        assert_operator (value - 20.0).abs, :<, (plain - 20.0).abs
    end

    def test_agreeing_parts_match_the_plain_weighted_fusion
        parts = [part("a", 20.0, 0.1), part("b", 20.0, 0.2),
                 part("c", 20.0, 0.05)]
        value, sigma, = Sensorium::Combine.robust(parts, 4.0)
        plain_value, plain_sigma = Sensorium::Combine.weighted(parts)
        assert_in_delta plain_value, value, 1e-9
        assert_in_delta plain_sigma, sigma, 1e-9
    end

    def test_a_zero_spread_does_not_crash
        parts = [part("a", 20.0, 0.001), part("b", 20.0, 0.001),
                 part("c", 20.0, 0.001)]
        value, sigma, = Sensorium::Combine.robust(parts, 4.0)
        assert value.finite?
        assert sigma.finite?
        assert_in_delta 20.0, value, 1e-9
    end

    # Two parts that disagree (the recorded room's wall-1 and valve-1,
    # 26 January 08:00): neither can be told the outlier, and a
    # Student-t fit settled on whichever σ was the smaller, a 3 %
    # change of one moving the value by 1.8 °C. Below three parts the
    # fusion is the inverse-variance one, and moves by a few hundredths.
    def test_two_parts_that_disagree_fuse_by_inverse_variance
        wall = part("wall-1", 17.27, 0.351)
        valve = part("valve-1", 19.55, 0.346)
        value, _, factors = Sensorium::Combine.robust([wall, valve], 4.0)
        plain_value, = Sensorium::Combine.weighted([wall, valve])
        assert_in_delta plain_value, value, 1e-9
        assert_equal [1.0], factors.values.uniq
        shrunk, = Sensorium::Combine.robust([wall.with(sigma: 0.351 * 0.97),
                                             valve], 4.0)
        assert_in_delta value, shrunk, 0.05
    end

    # The same two parts, 2.28 °C apart in a joint σ of 0.493: their
    # σ is the inverse-variance one widened 4.6 times, as wide as
    # their gap says.
    def test_two_parts_that_disagree_widen_their_sigma_by_their_gap
        parts = [part("wall-1", 17.27, 0.351), part("valve-1", 19.55, 0.346)]
        _, sigma, = Sensorium::Combine.robust(parts, 4.0)
        _, plain = Sensorium::Combine.weighted(parts)
        gap = 2.28 / Math.sqrt((0.351**2) + (0.346**2))
        assert_in_delta plain * gap, sigma, 1e-9
    end

    # Within their joint σ, two parts keep the inverse-variance σ.
    def test_two_parts_that_agree_keep_the_plain_sigma
        parts = [part("wall-1", 17.27, 0.351), part("valve-1", 17.5, 0.346)]
        _, sigma, = Sensorium::Combine.robust(parts, 4.0)
        assert_in_delta Sensorium::Combine.weighted(parts).last, sigma, 1e-9
    end

    private

    def part(device, value, sigma)
        Sensorium::Parts::Part.new(device:, raw: value, value:, sigma:,
                                   age: 0, time: nil, note: nil)
    end
end
