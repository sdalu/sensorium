# frozen_string_literal: true

require "test_helper"

class StatsTest < Minitest::Test
    Stats = Sensorium::Stats

    def test_quantiles_and_spread
        values = (1..11).map(&:to_f).shuffle(random: Random.new(1))
        assert_in_delta 6.0, Stats.median(values)
        assert_in_delta 8.0, Stats.spread(values)
    end

    def test_a_line_and_its_refusal
        base, slope = Stats.line([0.0, 1.0, 2.0], [1.0, 3.0, 5.0])
        assert_in_delta 1.0, base
        assert_in_delta 2.0, slope
        assert_nil Stats.line([1.0, 1.0], [0.0, 2.0])
    end

    # y = 1 + 2 x1 - 3 x2, and x2 a copy of x1: refused.
    def test_a_plane_and_its_refusal
        x1 = [0.0, 1.0, 2.0, 0.0, 1.0]
        x2 = [0.0, 0.0, 1.0, 2.0, 3.0]
        ys = x1.zip(x2).map { |a, b| 1 + (2 * a) - (3 * b) }
        found = Stats.plane(x1, x2, ys)
        [1.0, 2.0, -3.0].zip(found).each { |e, f| assert_in_delta e, f }
        assert_nil Stats.plane(x1, x1, ys)
    end

    def test_a_reading_is_carried_an_hour
        carried = Sensorium::Series.new(600)
                                   .carried({ 0 => 20.0, 6000 => 21.0 }, 3600)
        assert_in_delta 20.0, carried[3600]
        assert_nil carried[4200]
        assert_in_delta 21.0, carried[6000]
    end
end
