# frozen_string_literal: true

require "test_helper"

# How a Regression's terms are chosen together (Setup#joint): a
# regressor refused, by the narrowing or by the bins held out, leaves
# the others their turn. a explains 30 a unit until the last tenth of
# the bins, then nothing (a zone that stopped calling); b 20 a unit
# throughout. Every value is made up.
class RegressionChoiceTest < Minitest::Test
    DAY  = 86_400
    BINS = (0...1000).map { Time.utc(2024, 1, 1).to_i + (it * DAY) }.freeze
    CUT  = BINS[900]
    QUANTITY = Sensorium::Quantity.new(name: "energy", sigma: 0.5,
                                       drift: 5.0)

    def setup
        random = Random.new(4)
        @a, @b, noise = Array.new(3) do
            BINS.to_h { [it, random.rand] }
        end
        @y = BINS.to_h do |bin|
            [bin, (bin < CUT ? 30 * @a[bin] : 0) + (20 * @b[bin]) +
                noise[bin] - 0.5]
        end
    end

    # a narrows most, and the bins held out refuse it: b is kept.
    def test_a_refused_regressor_leaves_the_others_their_turn
        assert_operator ratio("a"), :<, ratio("b")
        assert_equal %w[b], learn.first.terms.keys
    end

    # A zone calling one day in thirty, tried after one acting
    # everywhere: fitted together, the first's term moves a little on
    # every bin, which is not the second acting there. It is kept.
    def test_a_rare_regressor_after_one_acting_everywhere
        random = Random.new(9)
        rare = BINS.to_h do |bin|
            [bin, (bin / DAY) % 30 == 7 ? 0.5 + random.rand : 0.0]
        end
        found = Sensorium::Regression.learn(rare_y(rare, random),
                                            { "b" => @b, "rare" => rare },
                                            setup_of, name: "house")
        assert_equal %w[b rare], found.first.terms.keys
    end

    private

    # 20 a unit of b, 30 a unit of rare, and noise.
    def rare_y(rare, random)
        BINS.to_h do |bin|
            [bin, (20 * @b[bin]) + (30 * rare[bin]) + random.rand - 0.5]
        end
    end

    def setup_of
        Sensorium::Setup.new(quantity: QUANTITY, bin: DAY, joint: true,
                             narrows: 0.95, min_samples: 100, min_part: 30)
    end

    def learn
        Sensorium::Regression.learn(@y, { "a" => @a, "b" => @b }, setup_of,
                                    name: "house")
    end

    # What the regressor alone leaves of the median's spread.
    def ratio(name)
        fit = Sensorium::Fit.new(@y, setup_of, levels: {})
        plain = fit.plain
        alone = Sensorium::Fit::Linear.joint(
            plain, { name => { "a" => @a, "b" => @b }[name] }, setup_of
        )
        alone.spread / plain.spread
    end
end
