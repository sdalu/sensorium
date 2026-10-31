# frozen_string_literal: true

module Sensorium
    class Fusion
        private

        def fused(name, at, reference, parts, context)
            counted = parts.select(&:value)
            value, sigma, factors = combine(reference, counted)
            fused = Fused.new(location: name, quantity: @setup.quantity.name,
                              at:, value: nil, sigma: nil,
                              inside: Estimate.new(value:, sigma:),
                              reference:, corrected: !reference.nil?,
                              parts: nil)
            outward(fused, shares(parts, factors), context)
        end

        # The reference's inverse-variance fusion, Student-t reweighted
        # (Combine.robust) once two parts or more count; the plain mean
        # without a reference. factors is flat (1.0, never "outlier")
        # wherever Combine.robust did not run.
        def combine(reference, counted)
            return [*Combine.mean(counted), flat(counted)] unless reference
            return [*Combine.weighted(counted), flat(counted)] if
                counted.size < 2
            Combine.robust(counted, @setup.quantity.robust_nu)
        end

        def flat(parts) = parts.to_h { [it, 1.0] }

        # { part => [its share of the value, why it is left out] },
        # weighted 1/σ² times its factor; below the quantity's
        # outlier_factor, noted "outlier".
        def shares(parts, factors)
            weighed = factors.to_h { |part, f| [part, f * base(part)] }
            total = [weighed.values.sum, Float::MIN].max
            parts.to_h do |part|
                [part, [weighed.fetch(part, 0) / total, note(part, factors)]]
            end
        end

        def base(part) = part.sigma ? 1 / (part.sigma**2) : 1.0

        def note(part, factors)
            factor = factors[part]
            return part.note unless factor && factor < outlier_factor
            "outlier"
        end

        def outlier_factor = @setup.quantity.outlier_factor

        # The fused value and each part's brought back as the quantity
        # reads, with the context given.
        def outward(fused, shares, context)
            inside = fused.inside
            value = back(inside.value, context)
            fused.with(value:, sigma: back_sigma(inside, value),
                       parts: shares.map do |part, (weight, note)|
                           Weighted.new(part:, weight:, note:,
                                        value: back(part.value, context))
                       end)
        end

        def back(value, context)
            value && @setup.quantity.transform.inverse(value, context)
        end

        def back_sigma(inside, value)
            return unless inside.sigma && value
            @setup.quantity.transform.sigma(inside.sigma, inside.value, value)
        end
    end
end
