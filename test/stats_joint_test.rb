# frozen_string_literal: true

require "test_helper"

# The joint fits a caller's own model takes (README, Toolkit): least
# squares with a ridge, and with every slope 0 or more. Every value is
# made up.
class StatsJointTest < Minitest::Test
    Stats = Sensorium::Stats

    # Two columns all but the same: alone, least squares puts y on
    # either, at random; a ridge shares it.
    def test_a_ridge_shares_what_two_columns_both_tell
        x1 = [1.0, 2.0, 3.0, 4.0, 5.0]
        x2 = [1.0, 2.0, 3.0, 4.0, 5.1]
        ys = x1.map { 2 * it }
        _, a, b = Stats.least_squares([x1, x2], ys, ridge: 0.1)
        assert_in_delta 0.95, a, 0.05
        assert_in_delta 0.95, b, 0.05
        assert_in_delta 2.0, Stats.least_squares([x1, x2], ys)[1], 1e-9
    end

    # The ridge scales with each column's own spread: the same columns
    # in other units share alike.
    def test_a_ridge_does_not_depend_on_the_units
        x1 = [1.0, 2.0, 4.0, 3.0, 5.0]
        x2 = [2.0, 1.0, 3.0, 5.0, 4.0]
        ys = x1.zip(x2).map { |a, b| a + b }
        found = Stats.least_squares([x1, x2], ys, ridge: 0.3)
        scaled = Stats.least_squares([x1.map { it * 1000 }, x2], ys,
                                     ridge: 0.3)
        assert_in_delta found[1], scaled[1] * 1000, 1e-9
        assert_in_delta found[2], scaled[2], 1e-9
    end

    # The fit with every slope 0 or more, against every subset of the
    # columns fitted by least squares: none leaves less.
    def test_nonnegative_is_the_best_fit_without_a_negative_slope
        random = Random.new(3)
        100.times do
            columns, ys = problem(random)
            found = Stats.nonnegative(columns, ys)
            assert(found.drop(1).none?(&:negative?))
            assert_operator squares(columns, ys, found), :<=,
                            (best(columns, ys) * (1 + 1e-9)) + 1e-12
        end
    end

    # y falls with x2: its slope is held at 0, and x1's fitted alone.
    def test_a_slope_that_would_be_negative_is_held_at_zero
        x1 = [0.0, 1.0, 2.0, 0.0, 1.0, 3.0]
        x2 = [0.0, 0.0, 1.0, 2.0, 3.0, 1.0]
        ys = x1.zip(x2).map { |a, b| 1 + (2 * a) - b }
        found = Stats.nonnegative([x1, x2], ys)
        assert_in_delta 0.0, found[2]
        Stats.least_squares([x1], ys).zip(found).each do |expected, got|
            assert_in_delta expected, got, 1e-12
        end
    end

    def test_nonnegative_refuses_a_constant_column
        assert_nil Stats.nonnegative([[1.0] * 4, [1.0, 2.0, 3.0, 4.0]],
                                     [1.0, 2.0, 3.0, 4.0])
    end

    private

    # Up to five columns, one a near copy of another, and y of them all
    # with slopes of either sign.
    def problem(random)
        columns = Array.new(1 + random.rand(5)) { draws(random) }
        columns << near(columns.first, random)
        slopes = columns.map { (random.rand * 4) - 2 }
        [columns, made(columns, [3.0, *slopes], draws(random))]
    end

    # Half the column, give or take a tenth.
    def near(column, random)
        column.map { (it * 0.5) + (random.rand * 0.1) }
    end

    def draws(random) = Array.new(30) { random.rand }

    # base + Σ slope × x, plus noise centred on 0.
    def made(columns, (base, *slopes), noise)
        noise.each_index.map do |i|
            base + columns.zip(slopes).sum { |x, b| b * x[i] } + noise[i] - 0.5
        end
    end

    # The least sum of squares of the subsets' fits without a negative
    # slope.
    def best(columns, ys)
        (0...(1 << columns.size)).filter_map do |mask|
            kept = columns.each_index.select { mask[it] == 1 }
            found = subset(columns, ys, kept) or next
            squares(columns, ys, found) if found.drop(1).none?(&:negative?)
        end.min
    end

    def subset(columns, ys, kept)
        return [Stats.mean(ys), *Array.new(columns.size, 0.0)] if kept.empty?
        found = Stats.least_squares(kept.map { columns[it] }, ys) or return
        [found.first, *columns.each_index.map do |j|
            kept.include?(j) ? found[kept.index(j) + 1] : 0.0
        end]
    end

    def squares(columns, ys, (base, *slopes))
        ys.each_index.sum do |i|
            (ys[i] - base - columns.zip(slopes).sum { |x, b| b * x[i] })**2
        end
    end
end
