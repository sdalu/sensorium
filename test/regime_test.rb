# frozen_string_literal: true

require "test_helper"

class RegimeTest < Minitest::Test
    def test_each_month_has_its_season
        assert_equal(%w[winter winter winter mid mid summer summer summer
                        summer mid winter winter],
                     (1..12).map { calendar.of(Time.new(2026, it, 15)) })
    end

    def test_a_span_covers_the_seasons_it_touches
        assert_equal %w[winter], covered([2025, 11, 1], [2026, 3, 31])
        assert_equal %w[winter mid summer], covered([2025, 10, 31],
                                                    [2026, 10, 31])
        assert_equal %w[winter mid], covered([2026, 3, 31], [2026, 4, 1])
    end

    def test_other_months_and_one_regime
        halves = Sensorium::Regime::Calendar.new("cold" => [*10..12, *1..3],
                                                 "warm" => [*4..9])
        assert_equal "warm", halves.of(Time.new(2026, 6, 1))
        constant = Sensorium::Regime::Constant.new
        assert_equal %w[all], constant.covered(Time.now, Time.now)
        assert_equal "all", constant.of(Time.now)
    end

    private

    def calendar = Sensorium::Regime::Calendar.new

    def covered(from, to) = calendar.covered(Time.new(*from), Time.new(*to))
end
