# frozen_string_literal: true

require "test_helper"

class StatsTest < Minitest::Test
    Stats = Sensorium::Stats
    # Three columns that vary apart.
    THREE = [[0.0, 1.0, 2.0, 0.0, 1.0, 3.0], [0.0, 0.0, 1.0, 2.0, 3.0, 1.0],
             [1.0, 0.0, 0.0, 1.0, 2.0, 5.0]].freeze

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

    # The general solver agrees with the line and the plane.
    def test_least_squares_agrees_with_the_line_and_the_plane
        x1, x2, ys = noisy
        assert_close Stats.line(x1, ys), Stats.least_squares([x1], ys)
        assert_close Stats.plane(x1, x2, ys),
                     Stats.least_squares([x1, x2], ys)
    end

    # y = 1 + 2 x1 - 3 x2 + 0.5 x3, exactly.
    def test_least_squares_on_three_columns
        assert_close [1.0, 2.0, -3.0, 0.5],
                     Stats.least_squares(THREE, three_ys)
    end

    # Refused with a column that is a sum of two others, or constant.
    def test_least_squares_refuses_columns_that_do_not_vary_apart
        x1, x2, = THREE
        sum = x1.zip(x2).map(&:sum)
        assert_nil Stats.least_squares([x1, x2, sum], three_ys)
        assert_nil Stats.least_squares([[1.0] * 6], three_ys)
    end

    def test_a_reading_is_carried_an_hour
        carried = Sensorium::Series.new(600)
                                   .carried({ 0 => 20.0, 6000 => 21.0 }, 3600)
        assert_in_delta 20.0, carried[3600]
        assert_nil carried[4200]
        assert_in_delta 21.0, carried[6000]
    end

    private

    def three_ys
        THREE.transpose.map { |a, b, c| 1 + (2 * a) - (3 * b) + (c / 2) }
    end

    # x1, x2 and y = 1 + 2 x1 - 3 x2 + noise, fifty of each.
    def noisy
        random = Random.new(5)
        x1, x2, noise = Array.new(3) { Array.new(50) { random.rand } }
        [x1, x2, x1.zip(x2, noise).map { |a, b, e| 1 + (2 * a) - (3 * b) + e }]
    end

    def assert_close(expected, found)
        assert_equal expected.size, found.size
        expected.zip(found).each { |e, f| assert_in_delta e, f, 1e-9 }
    end
end
