# frozen_string_literal: true

require "test_helper"

# A term judged with the bins it acts on weighing as much as the others
# (Fit::Balanced): one acting on a few bins is kept for what it
# explains there, which p10..p90 of all the bins never shows; one
# acting everywhere is judged as before. Every value is made up.
class BalancedTest < Minitest::Test
    BINS = (0...2000).to_a.freeze
    SETUP = Sensorium::Setup.new(quantity: Sensorium::Presets::TEMPERATURE,
                                 gain: false, rate: false)

    def setup
        random = Random.new(6)
        @noise = BINS.to_h { [it, (random.rand - 0.5) * 0.2] }
        # Acts on one bin in fifty, by 0.5 to 2.
        @rare = BINS.to_h { [it, it % 50 == 7 ? 0.5 + (it % 4 * 0.5) : 0.0] }
        @dense = BINS.to_h { [it, Math.sin(it / 30.0)] }
    end

    # Its bins are 2 % of all: p10..p90 of all the bins does not move.
    def test_a_term_acting_on_few_bins_is_kept
        diffs = BINS.to_h { [it, (3 * @rare[it]) + @noise[it]] }
        model = fit(diffs, series: { "rare" => @rare })
        assert_in_delta 3.0, model.series.fetch("rare"), 0.05
    end

    def test_a_term_that_explains_nothing_where_it_acts_is_not
        diffs = BINS.to_h { [it, @noise[it]] }
        assert_empty fit(diffs, series: { "rare" => @rare }).series
    end

    # Fewer than min_part bins: nothing to judge it on.
    def test_a_term_acting_on_too_few_bins_is_not_kept
        once = BINS.to_h { [it, it == 7 ? 1.0 : 0.0] }
        diffs = BINS.to_h { [it, (3 * once[it]) + @noise[it]] }
        assert_empty fit(diffs, series: { "once" => once }).series
    end

    # A regressor that varies everywhere is judged on all the bins
    # alike: the ratio is the plain spreads'.
    def test_a_term_acting_everywhere_is_judged_plainly
        before = BINS.to_h { [it, @dense[it] + @noise[it]] }
        after = @noise
        plain = Sensorium::Stats.spread(after.values) /
                Sensorium::Stats.spread(before.values)
        assert_in_delta plain, Sensorium::Fit::Balanced.ratio(before, after,
                                                              100, @dense)
    end

    # A hard Switch on in one bin in fifty is a term as the rare Series.
    def test_a_switch_seldom_on_is_kept
        on = BINS.select { it % 50 == 7 }.to_set
        diffs = BINS.to_h { [it, (on.include?(it) ? 1.0 : 0.0) + @noise[it]] }
        model = Sensorium::Fit.new(diffs, SETUP.with(min_part: 30),
                                   levels: {}, switches: { "s" => on }).model
        assert_in_delta 1.0, model.switches.fetch("s"), 0.05
    end

    private

    def fit(diffs, **terms)
        Sensorium::Fit.new(diffs, SETUP.with(min_part: 30), levels: {},
                                                            **terms).model
    end
end
