# frozen_string_literal: true

require "test_helper"

# Blend: keyed estimates made one, each weighted, its σ from theirs as
# independent errors. Fused locations here, and plain Estimates.
class BlendTest < Minitest::Test
    AT = Time.utc(2026, 1, 10, 20)

    def test_the_value_is_the_weighted_mean
        blended = blend({ "a" => 3, "b" => 1 })
        assert_in_delta 20.5, blended.value
        assert_in_delta 0.75, blended.shares["a"].weight
        assert_in_delta 0.25, blended.shares["b"].weight
    end

    # σ² = Σ (w / W)² σ²: (0.75 × 0.1)² + (0.25 × 0.2)².
    def test_sigma_from_the_shares_as_independent_errors
        blended = blend({ "a" => 3, "b" => 1 })
        assert_in_delta Math.hypot(0.075, 0.05), blended.sigma
    end

    def test_a_key_without_weight_does_not_count
        blended = blend({ "a" => 1 })
        assert_in_delta 20.0, blended.value
        assert_in_delta 0.0, blended.shares["b"].weight
        assert_in_delta 0.1, blended.sigma
    end

    # Weighted, but with no value: the others' shares fill its place.
    def test_an_estimate_without_value_does_not_count
        blended = blend({ "a" => 1, "b" => 1, "c" => 2 })
        assert_in_delta 0.0, blended.shares["c"].weight
        assert_in_delta 21.0, blended.value
    end

    def test_no_weight_anywhere_gives_no_value
        blended = blend({})
        assert_nil blended.value
        assert_nil blended.sigma
        assert_in_delta 0.0, blended.shares["a"].weight
    end

    # An uncorrected location (no reference) has no σ: neither has the
    # blend it counts in.
    def test_an_estimate_without_sigma_leaves_no_sigma
        blended = blend({ "a" => 1, "d" => 1 })
        assert_in_delta 21.5, blended.value
        assert_nil blended.sigma
    end

    def test_quantities_are_not_mixed
        humid = fused(50.0, 2.0).with(quantity: "humidity")
        assert_raises(ArgumentError) do
            Sensorium::Blend.new({ "h" => 1 }).of(all.merge("h" => humid))
        end
    end

    def test_a_weight_below_zero_is_refused
        assert_raises(ArgumentError) do
            Sensorium::Blend.new({ "a" => -1 }).of(all)
        end
    end

    def test_it_says_the_quantity_and_the_latest_moment
        blended = blend({ "a" => 1 })
        assert_equal "temperature", blended.quantity
        assert_equal AT, blended.at
    end

    # Any key, any estimate answering value and sigma, weights by a
    # callable: two floors by their area.
    def test_any_keys_estimates_and_weights
        floors = { ground: Sensorium::Estimate.new(value: 20.0, sigma: 0.1),
                   first: Sensorium::Estimate.new(value: 23.0, sigma: 0.1) }
        area = { ground: 80, first: 40 }
        blended = Sensorium::Blend.new(area.method(:fetch)).of(floors)
        assert_in_delta 21.0, blended.value
        assert_nil blended.quantity
        assert_nil blended.at
    end

    private

    def blend(weights) = Sensorium::Blend.new(weights).of(all)

    # a 20.0 ± 0.1, b 22.0 ± 0.2, c without a value, d 23.0 uncorrected.
    def all
        { "a" => fused(20.0, 0.1, at: AT - 600), "b" => fused(22.0, 0.2),
          "c" => fused(nil, nil), "d" => fused(23.0, nil) }
    end

    def fused(value, sigma, at: AT)
        Sensorium::Fusion::Fused.new(
            location: "x", quantity: "temperature", at:, value:, sigma:,
            inside: Sensorium::Estimate.new(value:, sigma:), reference: nil,
            corrected: !sigma.nil?, parts: []
        )
    end
end
