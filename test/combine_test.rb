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

    private

    def part(device, value, sigma)
        Sensorium::Parts::Part.new(device:, raw: value, value:, sigma:,
                                   age: 0, note: nil)
    end
end
