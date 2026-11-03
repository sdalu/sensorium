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

        # How many Student-t steps at most: parts split three ways
        # crawl between two of them for a few hundred before they
        # settle (221 at most over a year of the house's fusions, 314
        # over 4000 random ones).
        STEPS = 1000

        # [value, σ, { part => factor }] by Student-t reweighting (ν
        # `nu`) of the inverse-variance fusion, each part's factor
        # (nu + 1) / (nu + z²) on its standardised residual z, iterated
        # until it settles: the value moves less than 1e-6 (STEPS at
        # most). Every factor is (nu + 1) / nu, and σ equals the plain
        # inverse-variance one, when every part agrees. Below three
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
        # settled or `left` runs out.
        def iterated(parts, nu, value, left = STEPS)
            factors = reweighted(parts, nu, value)
            moved = averaged(parts, factors)
            return [moved, factors] if left.zero? ||
                                       (moved - value).abs < 1e-6
            iterated(parts, nu, moved, left - 1)
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
