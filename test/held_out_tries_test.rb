# frozen_string_literal: true

require "test_helper"

# Fit::HeldOut#keeps?: on the bins held out, a term they try (what it
# adds varies over them) is kept only when it narrows them; one they
# cannot try (it adds a constant there) is kept within TOLERANCE.
class HeldOutTriesTest < Minitest::Test
    BINS  = (0...100).to_a
    EVEN  = BINS.select(&:even?).to_set
    DIFFS = BINS.to_h { [it, it.even? ? 1.0 : -1.0] }.freeze
    PLAIN = Sensorium::Fit::Model.new(
        constant: 0.0, switches: {}, taus: {}, series: {}, gain: nil,
        neighbour: nil, coefficient: nil, rate: nil, residuals: {}
    )

    # On the even bins only, worth -0.02 there: the bins held out try
    # it, and it leaves them 1 % wider.
    def test_a_term_the_bins_try_and_widen_is_refused
        held_out = held_out(EVEN)
        tried = with_switch(-0.02)
        assert held_out.tries?(PLAIN, tried)
        assert_in_delta 1.01, held_out.narrowing(PLAIN, tried), 1e-9
        refute held_out.keeps?(PLAIN, tried)
    end

    def test_a_term_the_bins_try_and_narrow_is_kept
        held_out = held_out(EVEN)
        assert held_out.keeps?(PLAIN, with_switch(0.5))
    end

    # On in three of a hundred bins held out, whose diffs ramp from
    # -0.5 to 0.49: what it adds has a p10..p90 of 0, yet it switches
    # there, and the three bins try it: worth 0.5 where they show
    # nothing, it pushes them below p10, 3.8 % wider, and is refused.
    def test_a_term_on_in_a_few_of_the_bins_is_tried_there
        diffs = BINS.to_h { [it, (it / 100.0) - 0.5] }
        terms = Sensorium::Fit::Terms.new(switches: { "a" => Set[12, 13, 14] })
        held_out = Sensorium::Fit::HeldOut.new(diffs, {}, terms)
        tried = with_switch(0.5)
        assert held_out.tries?(PLAIN, tried)
        assert_in_delta 0.82 / 0.79, held_out.narrowing(PLAIN, tried), 1e-9
        refute held_out.keeps?(PLAIN, tried)
    end

    # On throughout the bins held out: a constant there, no evidence.
    def test_a_term_on_throughout_is_not_tried_and_is_kept
        held_out = held_out(BINS.to_set)
        tried = with_switch(-0.02)
        refute held_out.tries?(PLAIN, tried)
        assert held_out.keeps?(PLAIN, tried)
    end

    # Never on there, with constants and diffs as a fit leaves them:
    # what it adds varies by the rounding only, and is not tried.
    def test_a_term_varying_by_rounding_only_is_not_tried
        diffs = BINS.to_h { [it, 0.3137 * Math.sin(it)] }
        plain = PLAIN.with(constant: 0.2137)
        tried = plain.with(constant: 0.1981, switches: { "a" => -0.0173 })
        terms = Sensorium::Fit::Terms.new(switches: { "a" => Set.new })
        held_out = Sensorium::Fit::HeldOut.new(diffs, {}, terms)
        refute held_out.tries?(plain, tried)
        assert held_out.keeps?(plain, tried)
    end

    private

    def with_switch(term) = PLAIN.with(switches: { "a" => term })

    def held_out(on)
        terms = Sensorium::Fit::Terms.new(switches: { "a" => on })
        Sensorium::Fit::HeldOut.new(DIFFS, {}, terms)
    end
end
