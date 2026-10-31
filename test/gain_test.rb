# frozen_string_literal: true

require "test_helper"

# The gain fitted with the reference's own noise in mind (Deming): a
# sensor 20 % high against a reference that swings ±3 and is read with
# a noise of σ 0.3. Least squares on the noisy reference would find
# about 0.176.
class GainTest < Minitest::Test
    BINS = (0...2000).to_a

    def setup
        random = Random.new(11)
        @true = BINS.to_h { [it, 20 + (3 * Math.sin(it / 50.0))] }
        @read = @true.to_h { |bin, r| [bin, r + gauss(random, 0.3)] }
    end

    def test_a_deming_line
        base, slope = Sensorium::Stats.deming([0.0, 1.0, 2.0, 3.0],
                                              [0.0, 2.0, 1.0, 3.0], 1.0)
        assert_in_delta 1.0, slope
        assert_in_delta 0.0, base
    end

    def test_the_gain_is_not_biased_by_the_references_noise
        model = fit(0.3)
        assert_in_delta 0.2, model.gain, 0.008
        assert_in_delta(-0.7, model.constant, 0.2)
    end

    # The reference said noiseless: least squares, biased.
    def test_without_the_references_noise_least_squares
        assert_in_delta 0.176, fit(1e-9).gain, 0.008
    end

    private

    def gauss(random, sigma)
        sigma * Math.sqrt(-2 * Math.log(1 - random.rand)) *
            Math.cos(2 * Math::PI * random.rand)
    end

    def fit(sigma)
        diffs = BINS.to_h do |bin|
            [bin, (1.2 * @true[bin]) - 0.7 - @read[bin]]
        end
        quantity = Sensorium::Quantity.new(name: "t", sigma:, drift: 1.0)
        setup = Sensorium::Setup.new(quantity:)
        Sensorium::Fit.new(diffs, setup, levels: @read).model
    end
end
