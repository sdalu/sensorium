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

        # [intercept, slope] of y on x when both carry an error, ratio
        # the variance of y's over x's (Deming regression); nil when they
        # do not vary together.
        def deming(xs, ys, ratio)
            cx, cy = [xs, ys].map { centred(it) }
            sxy = dot(cx, cy)
            return if sxy.zero?
            slope = deming_slope(dot(cy, cy) - (ratio * dot(cx, cx)),
                                 ratio, sxy)
            [mean(ys) - (slope * mean(xs)), slope]
        end

        # (d + root) / 2sxy, as 2·ratio·sxy / (root - d) when d < 0 so
        # that a large ratio does not cancel to nothing.
        def deming_slope(d, ratio, sxy)
            root = Math.sqrt((d**2) + (4 * ratio * (sxy**2)))
            return (d + root) / (2 * sxy) unless d.negative?
            2 * ratio * sxy / (root - d)
        end

        # [intercept, gain] of y = s - x on x, where x is read with an
        # error σ: a Deming line of s on x, its variance ratio the
        # error s keeps once x's is taken out (at least floor²) over
        # σ², re-estimated from what the line leaves until it settles.
        # Least squares when σ is not positive.
        def gain(xs, ys, sigma, floor)
            ss = xs.zip(ys).map(&:sum)
            found = line(xs, ss) or return
            if sigma.positive?
                found = settled(xs, ss, found, sigma, floor) or return
            end
            [found.first, found.last - 1]
        end

        def settled(xs, ss, found, sigma, floor)
            20.times do
                ratio = own(xs, ss, found, sigma, floor) / (sigma**2)
                fresh = deming(xs, ss, ratio) or return
                return fresh if (fresh.last - found.last).abs < 1e-9
                found = fresh
            end
            found
        end

        # The variance of the error s keeps on its own.
        def own(xs, ss, (base, slope), sigma, floor)
            left = xs.zip(ss).map { |x, s| s - base - (slope * x) }
            [((spread(left) / P10_P90)**2) - ((slope * sigma)**2),
             floor**2].max
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

        # The covariance of two series of the same length (over n).
        def covariance(xs, ys) = dot(centred(xs), centred(ys)) / xs.size

        def mean(values) = values.sum.fdiv(values.size)
    end
end
require_relative "stats/least_squares"
