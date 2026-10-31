# frozen_string_literal: true

require "test_helper"

# The joint refit after the greedy fit, on made-up bins: a Switch on
# fifty bins in a hundred and the gap to a neighbour, ±2 at random,
# 1.5 wider while it is on, so the Switch's median, fitted first, takes
# in some of the neighbour's term.
class RefitTest < Minitest::Test
    BINS  = (0...2000).to_a
    ON    = BINS.select { (it / 50).even? }.to_set
    SETUP = Sensorium::Setup.new(quantity: Sensorium::Presets::TEMPERATURE,
                                 gain: false, rate: false)

    def setup
        random = Random.new(3)
        @noise = BINS.to_h { [it, (random.rand - 0.5) * 0.05] }
        @swing = BINS.to_h { [it, (random.rand - 0.5) * 4] }
    end

    # The truth: 0.3, the Switch 0.5, the neighbour 0.3.
    def test_the_refit_comes_closer_to_the_true_terms
        model = fit(gaps(1.5))
        assert_in_delta 0.5, model.switches.fetch("s"), 0.01
        assert_in_delta 0.3, model.coefficient, 0.01
        assert_in_delta 0.3, model.constant, 0.01
        assert_operator model.spread, :<, 0.06
    end

    # One bin in twelve while on reads 20 too high: the medians shrug
    # it off (the Switch's moves by some 0.06), least squares would not
    # (by 20 / 12), so the refit, wider, is not kept.
    def test_a_wider_refit_is_not_kept
        spiked = ON.select { (it % 12).zero? }.to_set
        model = fit(gaps(0)) { spiked.include?(it) ? 20.0 : 0.0 }
        assert_in_delta 0.5, model.switches.fetch("s"), 0.1
        assert_in_delta 0.3, model.coefficient, 0.1
    end

    private

    def gaps(wider)
        BINS.to_h do |bin|
            [bin, @swing[bin] + (ON.include?(bin) ? wider : 0)]
        end
    end

    def fit(gaps)
        diffs = BINS.to_h do |bin|
            spike = block_given? ? yield(bin) : 0
            [bin, 0.3 + (ON.include?(bin) ? 0.5 : 0) + (0.3 * gaps[bin]) +
                @noise[bin] + spike]
        end
        Sensorium::Fit.new(diffs, SETUP, levels: BINS.to_h { [it, 20.0] },
                                         switches: { "s" => ON },
                                         candidates: { "n" => gaps }).model
    end
end
