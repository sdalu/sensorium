# frozen_string_literal: true

module Sensorium
    # The few statistics the learner needs.
    module Stats
        module_function

        # The value at fraction f of the sorted values (nearest rank).
        def quantile(values, fraction)
            sorted = values.sort
            sorted[(fraction * (sorted.size - 1)).round]
        end

        def median(values) = quantile(values, 0.5)

        # p90 - p10: how widely the values spread, outliers aside.
        def spread(values)
            quantile(values, 0.9) - quantile(values, 0.1)
        end

        # [intercept, slope] of y on x, least squares; nil when x does
        # not vary.
        def line(xs, ys)
            mx  = mean(xs)
            my  = mean(ys)
            sxx = xs.sum { (it - mx)**2 }
            return if sxx.zero?
            slope = xs.zip(ys).sum { |x, y| (x - mx) * (y - my) } / sxx
            [my - (slope * mx), slope]
        end

        # [intercept, a, b] of y on x1 and x2, least squares; nil when
        # they do not vary apart.
        def plane(x1s, x2s, ys)
            found = slopes(*[x1s, x2s, ys].map { centred(it) }) or return
            a, b = found
            [mean(ys) - (a * mean(x1s)) - (b * mean(x2s)), a, b]
        end

        # The normal equations of centred columns, solved.
        def slopes(c1, c2, cy)
            s11, s12, s22, s1y, s2y =
                [[c1, c1], [c1, c2], [c2, c2], [c1, cy], [c2, cy]]
                .map { dot(*it) }
            det = (s11 * s22) - (s12**2)
            return unless det.positive? && det > 1e-9 * s11 * s22
            [cross(s22, s1y, s12, s2y) / det, cross(s11, s2y, s12, s1y) / det]
        end

        def cross(a, b, c, d) = (a * b) - (c * d)

        def centred(values)
            m = mean(values)
            values.map { it - m }
        end

        def dot(xs, ys) = xs.zip(ys).sum { |x, y| x * y }

        def mean(values) = values.sum.fdiv(values.size)
    end
end
