# frozen_string_literal: true

module Sensorium
    module Stats
        module_function

        # [intercept, *slopes] of y on any number of columns, least
        # squares: the normal equations of the centred columns, solved by
        # Gaussian elimination, each column on its own row (the matrix is
        # a sum of squares: no pivot to search); nil when a column does
        # not vary (Stats.constant?), or not apart from the others (what
        # it keeps once those before it are taken out below 1e-9 of its
        # own sum of squares, as Stats.plane refuses: 1 - rho² for two,
        # in either order and any units). ridge: a penalty on the
        # slopes, each column's own
        # sum of squares times ridge added to it (a ridge regression
        # that does not depend on the columns' units; 0, none): columns
        # that nearly tell the same share it rather than swing apart.
        # The intercept is never penalised.
        def least_squares(columns, ys, ridge: 0.0)
            return if columns.any? { constant?(it) }
            centred = columns.map { centred(it) }
            slopes = eliminated(normal(centred, centred(ys), ridge)) or
                return
            [intercept(columns, ys, slopes), *slopes]
        end

        # The intercept of y on the columns, given their slopes.
        def intercept(columns, ys, slopes)
            mean(ys) - columns.zip(slopes).sum { |x, b| b * mean(x) }
        end

        # The augmented matrix [Σ cᵢcⱼ (× (1 + ridge) on the diagonal)
        # | Σ cᵢy].
        def normal(centred, cy, ridge = 0.0)
            centred.each_with_index.map do |ci, i|
                row = centred.map { dot(ci, it) }
                row[i] *= 1 + ridge if ridge.positive?
                [*row, dot(ci, cy)]
            end
        end

        # The solution of the augmented matrix, nil when singular.
        def eliminated(rows)
            limits = rows.each_with_index.map { |row, i| 1e-9 * row[i] }
            back(rows) if rows.each_index.all? { pivoted?(rows, it, limits) }
        end

        # Whether column j keeps more than its limit; if so, column j is
        # cleared below it.
        def pivoted?(rows, j, limits)
            return false unless rows[j][j] > limits[j]
            reduce(rows, j)
            true
        end

        # Column j cleared below row j.
        def reduce(rows, j)
            ((j + 1)...rows.size).each do |i|
                factor = rows[i][j] / rows[j][j]
                rows[i] = rows[i].zip(rows[j]).map { |a, b| a - (factor * b) }
            end
        end

        # Back substitution of an upper triangular augmented matrix.
        def back(rows)
            x = Array.new(rows.size)
            (rows.size - 1).downto(0) { x[it] = solved(rows[it], it, x) }
            x
        end

        # Row i solved for x[i], the x after it known.
        def solved(row, i, x)
            known = ((i + 1)...x.size).sum { row[it] * x[it] }
            (row[x.size] - known) / row[i]
        end
    end
end
