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

    # Three parts split three ways, each pair apart by 2.3 σ or more:
    # the reweighting crawls between two of them for some 250 steps
    # before it settles. The value is one a further step leaves where
    # it is; at the 21st step it was 2.5 σ away.
    def test_three_parts_split_three_ways_settle
        parts = [part("a", -0.14, 0.38), part("b", -1.11, 0.18),
                 part("c", 0.93, 0.16)]
        value, = Sensorium::Combine.robust(parts, 4.0)
        factors = Sensorium::Combine.reweighted(parts, 4.0, value)
        assert_in_delta value, Sensorium::Combine.averaged(parts, factors),
                        1e-6
    end

    # Three parts near the point where the far one's pull gives way
    # (one of about 200 000 random three-part fusions): the steps creep
    # through a bottleneck, 5e-6 at a time for 1800 of them, where the
    # 1000-step guard returned 6.938 (σ 0.312), 1.7 σ short of the 7.457
    # the steps settle at. The crawl is taken through at once, and the
    # value is the one the steps alone reach, within the 1e-6 they
    # settle by.
    def test_a_crawl_through_a_bottleneck_settles_past_it
        parts = [part("a", 6.460762157811805, 0.33428169888080045),
                 part("b", 7.7606917912233655, 0.2589396069249798),
                 part("c", 0.8510774383815356, 0.24351478926535491)]
        value, = Sensorium::Combine.robust(parts, 4.0)
        assert_in_delta settled(parts, 4.0), value, 1e-5
        assert_in_delta 7.457, value, 1e-3
    end

    # The same with the first part 3e-5 lower: the bottleneck's least
    # step is now below zero (-6e-7), a pair of fixed points, and the
    # steps settle at the first of them, 6.936, in 13 571 steps; the
    # guard returned 6.935. The crawl is taken through to that one, not
    # past it.
    def test_a_crawl_that_ends_in_the_bottleneck_settles_there
        parts = [part("a", 6.460732157811805, 0.33428169888080045),
                 part("b", 7.7606917912233655, 0.2589396069249798),
                 part("c", 0.8510774383815356, 0.24351478926535491)]
        value, = Sensorium::Combine.robust(parts, 4.0)
        assert_in_delta settled(parts, 4.0), value, 1e-6
        assert_in_delta 6.936, value, 1e-3
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

    # The Student-t steps alone, no guard, until one moves less than
    # 1e-13.
    def settled(parts, nu)
        combine = Sensorium::Combine
        value = combine.weighted(parts).first
        loop do
            moved = combine.averaged(parts,
                                     combine.reweighted(parts, nu, value))
            return moved if (moved - value).abs < 1e-13
            value = moved
        end
    end

    def part(device, value, sigma)
        Sensorium::Parts::Part.new(device:, raw: value, value:, sigma:,
                                   age: 0, time: nil, note: nil)
    end
end
