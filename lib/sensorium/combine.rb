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

        # The part furthest from what the others say, if it is more than
        # `limit` σ away; nil with fewer than three.
        def outlier(parts, limit)
            return if parts.size < 3
            worst = parts.max_by { distance(it, parts - [it]) }
            worst if distance(worst, parts - [worst]) > limit
        end

        # How many σ apart a part and the others' fusion are.
        def distance(part, others)
            value, sigma = weighted(others)
            (part.value - value).abs / Math.hypot(part.sigma, sigma)
        end

        # { part => [its share of the value, why it is left out] }, 0 for
        # those left out.
        def shares(parts, kept, outlier)
            weights = kept.to_h { [it, it.sigma ? 1 / (it.sigma**2) : 1.0] }
            total = [weights.values.sum, Float::MIN].max
            parts.to_h do |part|
                note = part == outlier ? "outlier" : part.note
                [part, [weights.fetch(part, 0) / total, note]]
            end
        end
    end
end
