# frozen_string_literal: true

module Sensorium
    # The arithmetic of Fusion, on Parts::Part.
    module Combine
        module_function

        # [value, σ] by inverse variance; [nil, nil] of nothing.
        def weighted(parts)
            return [nil, nil] if parts.empty?
            weights = parts.map { 1 / (it.sigma**2) }
            total = weights.sum
            [parts.zip(weights).sum { |part, w| part.value * w } / total,
             1 / Math.sqrt(total)]
        end

        def mean(parts)
            return [nil, nil] if parts.empty?
            [parts.sum(&:value).fdiv(parts.size), nil]
        end

        # How many Student-t steps before a crawl is taken through at
        # once (crossed): parts split three ways crawl between two of
        # them for a few hundred before they settle (221 at most over a
        # year of the house's fusions, 314 over 4000 random ones); near
        # the point where a far part's pull gives way, for thousands.
        STEPS = 1000

        # The golden ratio's inverse, the cut of least.
        GOLD = (Math.sqrt(5) - 1) / 2

        # [value, σ, { part => factor }] by Student-t reweighting (ν
        # `nu`) of the inverse-variance fusion, each part's factor
        # (nu + 1) / (nu + z²) on its standardised residual z, iterated
        # until it settles: the value moves less than 1e-6 (a crawl past
        # STEPS crossed at once, iterated). Every factor is
        # (nu + 1) / nu, and σ equals the plain inverse-variance one,
        # when every part agrees. Below three
        # parts, few(parts).
        def robust(parts, nu)
            return few(parts) if parts.size < 3
            value, factors = iterated(parts, nu, weighted(parts).first)
            [value, spread(parts, factors, nu), factors]
        end

        # [value, σ, { part => 1.0 }] of fewer than three parts: two
        # that disagree cannot tell which is off, and a Student-t fit
        # would settle on either, the one with the smaller σ. The
        # inverse-variance fusion, its σ widened by disagreement.
        def few(parts)
            value, sigma = weighted(parts)
            [value, sigma && (sigma * disagreement(parts)),
             parts.to_h { [it, 1.0] }]
        end

        # How far two parts are apart in their joint σ,
        # |a - b| / √(σa² + σb²), never below 1; 1 of one part.
        def disagreement(parts)
            return 1.0 unless parts.size == 2
            a, b = parts
            gap = (a.value - b.value).abs /
                  Math.sqrt((a.sigma**2) + (b.sigma**2))
            [gap, 1.0].max
        end

        # One Student-t step from `value`, and another unless it
        # settled; once `left` runs out the steps are crawling, and the
        # crawl is taken through at once (crossed), the steps starting
        # over. At most `crawls` of them: a crawl is a pair of
        # stationary points of the Student-t likelihood, real or nearly
        # so, of 2n - 1 at most, one of them the end.
        def iterated(parts, nu, value, left = STEPS, crawls = parts.size - 1)
            factors = reweighted(parts, nu, value)
            moved = averaged(parts, factors)
            return [moved, factors] if (moved - value).abs < 1e-6
            if left.positive?
                return iterated(parts, nu, moved, left - 1, crawls)
            end
            return [moved, factors] if crawls.zero?
            iterated(parts, nu, crossed(parts, nu, moved), STEPS, crawls - 1)
        end

        # Where a crawl from `value` leads. The step, as a function of
        # the value, is small there and shrinking: either it dips near
        # zero ahead and grows again, a bottleneck the steps creep
        # through, or it heads for a zero it nears slowly. Mirrored so
        # that it heads up (sign), probed ahead and taken through.
        def crossed(parts, nu, value)
            gap = ->(v) { averaged(parts, reweighted(parts, nu, v)) - v }
            sign = gap.call(value).positive? ? 1 : -1
            step = ->(u) { sign * gap.call(sign * u) }
            sign * through(step, sign * value)
        end

        # The crawl's end: `far`, where the step has grown past the one
        # at `from` or turned negative; the least step between the two
        # still positive: a bottleneck, crossed at `far`; or else the
        # first zero, where the plain steps would have settled.
        def through(step, from)
            far = probed(step, from)
            low = least(step, from, far)
            bound = step.call(low).positive? ? far : low
            step.call(bound).positive? ? bound : bisected(step, from, bound)
        end

        # The first of the points at doubling distances ahead of `from`
        # where the step is not a crawl's: past the one at `from`, or
        # not positive (beyond the last part it never is).
        def probed(step, from)
            first = step.call(from)
            distance = first
            loop do
                distance *= 2
                probe = step.call(from + distance)
                return from + distance unless probe.positive? &&
                                              probe <= first
            end
        end

        # Where the step is least between `from` and `to`, by golden
        # section.
        def least(step, from, to)
            narrowed(from, to) do |a, b|
                low = b - (GOLD * (b - a))
                high = a + (GOLD * (b - a))
                step.call(low) < step.call(high) ? [a, high] : [low, b]
            end
        end

        # The first zero of the step between `from` (positive) and `to`
        # (not), by bisection.
        def bisected(step, from, to)
            narrowed(from, to) do |a, b|
                mid = (a + b) / 2
                step.call(mid).positive? ? [mid, b] : [a, mid]
            end
        end

        # The middle of `from`..`to` narrowed 60 times to what the block
        # keeps of it.
        def narrowed(from, to)
            60.times { from, to = yield(from, to) }
            (from + to) / 2
        end

        # { part => factor }, its Student-t weight against `value`.
        def reweighted(parts, nu, value)
            parts.to_h do |part|
                z = (part.value - value) / part.sigma
                [part, (nu + 1) / (nu + (z**2))]
            end
        end

        # The weighted mean by factor / σ².
        def averaged(parts, factors)
            weights = parts.to_h { [it, factors[it] / (it.sigma**2)] }
            total = weights.values.sum
            parts.sum { |part| part.value * weights[part] } / total
        end

        # 1 / sqrt(Σ(factor / σ²) × ν / (ν + 1)).
        def spread(parts, factors, nu)
            total = parts.sum { |part| factors[part] / (part.sigma**2) }
            1 / Math.sqrt(total * nu / (nu + 1))
        end
    end
end
