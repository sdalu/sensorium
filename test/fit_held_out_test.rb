# frozen_string_literal: true

require "test_helper"

# Fit::Validated: terms chosen without the last tenth of the bins, kept
# only when they leave those no wider, then fitted on all the bins.
class FitHeldOutTest < Minitest::Test
    BINS = (0...1000).to_a
    A = BINS.select { it % 4 < 2 }.to_set
    LATE = 900

    def setup
        @reference = wave(20, 3, 50.0)
        @gaps = BINS.to_h { [it, @reference[it] - 10 - Math.cos(it / 37.0)] }
        @series = wave(50, 40, 23.0)
        random = Random.new(7)
        @noise = BINS.to_h { [it, (random.rand - 0.5) * 0.02] }
    end

    # Followed while fitted, reversed on the bins held out: the term
    # narrows the one and widens the other.
    def test_a_term_the_bins_held_out_deny_is_refused
        model = validated(switches: { "a" => A }) do |bin|
            sign = bin < LATE ? 1.0 : -1.0
            A.include?(bin) ? sign : 0.0
        end
        assert_empty model.switches
    end

    def test_a_term_the_bins_held_out_confirm_is_fitted_on_all
        model = validated(switches: { "a" => A }) do |bin|
            A.include?(bin) ? 0.5 : 0.0
        end
        assert_in_delta 0.5, model.switches["a"], 0.02
        assert_equal BINS.size, model.residuals.size
    end

    # Worth 1 °C while fitted, 0.7 on the bins held out: kept, but its
    # narrowing is what the bins held out confirm, and the model's
    # widths are to be widened by as much.
    def test_a_term_the_bins_held_out_confirm_less_is_widened
        learned = learned(switches: { "a" => A }) do |bin|
            worth = bin < LATE ? 1.0 : 0.7
            A.include?(bin) ? worth : 0.0
        end
        refute_empty learned.fit.model.switches
        assert_operator learned.inflation, :>, 2.0
    end

    # The widening is set against the refit on all the bins, whose
    # widths it widens: a term the bins held out narrow at all ends no
    # wider than the plain constant.
    def test_a_widened_term_stays_narrower_than_the_constant
        learned = learned(switches: { "a" => A }) do |bin|
            worth = bin < LATE ? 1.0 : 0.7
            A.include?(bin) ? worth : 0.0
        end
        plain = learned.fit.plain.residuals.values
        assert_operator learned.model.spread * learned.inflation, :<,
                        Sensorium::Stats.spread(plain)
    end

    def test_a_term_the_bins_held_out_confirm_is_not_widened
        learned = learned(switches: { "a" => A }) do |bin|
            A.include?(bin) ? 0.5 : 0.0
        end
        assert_in_delta 1.0, learned.inflation, 0.1
    end

    def test_the_constant_alone_is_not_widened
        assert_in_delta 1.0, learned { 0.3 }.inflation
    end

    # 150 bins: holding 100 out leaves 50, short of min_part; the gain
    # the sensor follows, which needs no min_part, is not tried.
    def test_too_few_bins_leave_the_constant_alone
        model = validated(bins: BINS.first(150)) { 0.05 * @reference[it] }
        assert_nil model.gain
        assert_equal 150, model.residuals.size
    end

    def test_the_full_fit_has_every_term
        model = full_fit.model
        assert_equal [%w[a], %w[s], "n"],
                     [model.switches.keys, model.series.keys, model.neighbour]
        assert model.gain
    end

    # What HeldOut predicts on the bins a model was fitted on is what
    # the Fit left there.
    def test_held_out_residuals_are_the_fits_own
        fit = full_fit
        made = Sensorium::Fit::HeldOut.new(diffs { full_model(it) },
                                           @reference, fit.terms)
                                      .residuals(fit.model)
        fit.model.residuals.each do |bin, r|
            assert_in_delta r, made[bin], 1e-9
        end
    end

    private

    def wave(mean, swing, period)
        BINS.to_h { [it, mean + (swing * Math.sin(it / period))] }
    end

    def full_model(bin)
        0.1 + (A.include?(bin) ? 3.0 : 0.0) + (0.02 * @series[bin]) +
            (0.05 * @reference[bin]) - (0.2 * @gaps[bin])
    end

    def full_fit
        Sensorium::Fit.new(diffs { full_model(it) }, setup_of,
                           levels: @reference, switches: { "a" => A },
                           series: { "s" => @series },
                           candidates: { "n" => @gaps })
    end

    def diffs(bins = BINS) = bins.to_h { [it, yield(it) + @noise[it]] }

    def setup_of
        Sensorium::Setup.new(quantity: Sensorium::Presets::TEMPERATURE)
    end

    def validated(bins: BINS, switches: {}, &)
        Sensorium::Fit::Validated.fit(diffs(bins, &), setup_of,
                                      levels: @reference, switches:).model
    end

    def learned(switches: {}, &)
        Sensorium::Fit::Validated.learn(diffs(&), setup_of,
                                        levels: @reference, switches:)
    end
end
