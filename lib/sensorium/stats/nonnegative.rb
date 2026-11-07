# frozen_string_literal: true

module Sensorium
    module Stats
        module_function

        # [intercept, *slopes] of y on the columns, least squares with
        # every slope 0 or more, the intercept free (Lawson and
        # Hanson's active set): a slope least squares would make
        # negative is held at 0, and the others fitted without it. For
        # terms that can only add (a room's valve open adds gas, never
        # takes it away). ridge as least_squares takes it. nil when a
        # column does not vary, or those fitted together do not vary
        # apart.
        def nonnegative(columns, ys, ridge: 0.0)
            return if columns.any? { constant?(it) }
            slopes = Array.new(columns.size, 0.0)
            passive = []
            (3 * columns.size).times do
                j = entering(columns, ys, slopes, passive) or break
                found = feasible(columns, ys, passive + [j], slopes,
                                 ridge) or return
                slopes, passive = found
            end
            [intercept(columns, ys, slopes), *slopes]
        end

        # The column not fitted yet whose slope, grown from 0, would
        # narrow what the fit leaves most (the largest Σ cⱼ r, both
        # centred); nil when none would, beyond the rounding.
        def entering(columns, ys, slopes, passive)
            left = centred(leftover(columns, ys, slopes))
            found = columns.each_index.filter_map do |j|
                next if passive.include?(j)
                cj = centred(columns[j])
                gain = dot(cj, left)
                [j, gain] if gain > ROUNDING * Math.sqrt(dot(cj, cj) *
                                                         dot(left, left))
            end
            found.max_by(&:last)&.first
        end

        # [slopes, passive] once the columns fitted (passive) all have
        # a positive slope: each time one would not, every slope moves
        # from where it was toward the fit only as far as keeps them
        # all 0 or more, and those at 0 leave. nil when the fit is
        # refused.
        def feasible(columns, ys, passive, slopes, ridge)
            (passive.size + 1).times do
                fitted = fitted(columns, ys, passive, ridge) or return
                return [placed(fitted, columns.size), passive] if
                    fitted.values.all?(&:positive?)
                slopes = toward(slopes, fitted)
                passive = passive.select { slopes[it].positive? }
                return [slopes, passive] if passive.empty?
            end
            nil
        end

        # { column => slope } of the passive columns fitted together.
        def fitted(columns, ys, passive, ridge)
            found = least_squares(passive.map { columns[it] }, ys,
                                  ridge:) or return
            passive.zip(found.drop(1)).to_h
        end

        # The slopes moved toward those fitted as far as keeps every one
        # 0 or more; those it brings to 0 (within the rounding) at 0.
        def toward(slopes, fitted)
            step = step(slopes, fitted)
            moved = slopes.each_index.map do |j|
                next 0.0 unless fitted.key?(j)
                slopes[j] + (step * (fitted[j] - slopes[j]))
            end
            least = ROUNDING * [moved.map(&:abs).max, 1.0].max
            moved.map { it > least ? it : 0.0 }
        end

        # How far toward the fit the slopes may move, 0..1: as far as
        # the first that would cross 0 reaches it.
        def step(slopes, fitted)
            fitted.filter_map do |j, z|
                slopes[j] / (slopes[j] - z) unless z.positive?
            end.min
        end

        def placed(fitted, size) = Array.new(size) { fitted.fetch(it, 0.0) }

        # y less the slopes' part of it.
        def leftover(columns, ys, slopes)
            ys.each_index.map do |i|
                ys[i] - columns.zip(slopes).sum { |x, b| b * x[i] }
            end
        end
    end
end
