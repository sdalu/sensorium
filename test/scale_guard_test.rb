# frozen_string_literal: true

require "test_helper"

# The scale guard: a linear term that leaves |1 + gain + coefficient|
# below Setup#scale_floor is refused, since correcting a reading
# divides by it. Made-up bins as FitTest's: a reference swinging ±3
# around 20, a neighbour ±5 around 10.
class ScaleGuardTest < Minitest::Test
    BINS = (0...1000).to_a

    def setup
        @reference = BINS.to_h { [it, 20 + (3 * Math.sin(it / 50.0))] }
        @gaps = BINS.to_h { [it, @reference[it] - neighbour(it)] }
        random = Random.new(7)
        @noise = BINS.to_h { [it, (random.rand - 0.5) * 0.02] }
    end

    # Tado on MadHouse's humidity: k about -0.9, 1 + k = 0.1.
    def test_a_coefficient_of_minus_0_9_is_refused
        model = fit { -0.9 * @gaps[it] }
        assert_nil model.neighbour
        assert_nil model.coefficient
        assert_nil model.gain
    end

    def test_a_coefficient_within_the_floor_is_kept
        model = fit { -0.4 * @gaps[it] }
        assert_in_delta(-0.4, model.coefficient, 0.005)
    end

    def test_the_floor_is_a_setting
        assert_in_delta 0.5, setup_with.scale_floor
        model = fit(scale_floor: 0.05) { -0.9 * @gaps[it] }
        assert_in_delta(-0.9, model.coefficient, 0.005)
    end

    # The neighbour alone passes (it takes some of the gain: about
    # 1 - 0.37), the pair with the gain does not (1 - 0.25 - 0.3): the
    # Fit keeps the neighbour alone.
    def test_a_pair_is_refused_and_the_single_kept
        model = fit { paired(it) }
        assert_nil model.gain
        assert_equal "n", model.neighbour
        assert_in_delta(-0.37, model.coefficient, 0.01)
        model = fit(scale_floor: 0.3) { paired(it) }
        assert_in_delta(-0.3, model.coefficient, 0.005)
    end

    private

    def neighbour(bin) = 10 + (5 * Math.cos(bin / 37.0))

    def paired(bin) = (-0.25 * @reference[bin]) - (0.3 * @gaps[bin])

    def setup_with(**settings)
        Sensorium::Setup.new(quantity: Sensorium::Presets::TEMPERATURE,
                             **settings)
    end

    def fit(**settings)
        diffs = BINS.to_h { [it, yield(it) + @noise[it]] }
        Sensorium::Fit.new(diffs, setup_with(**settings),
                           levels: @reference,
                           candidates: { "n" => @gaps }).model
    end
end
