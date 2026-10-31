# frozen_string_literal: true

module Sensorium
    class Fusion
        private

        def fused(name, at, reference, parts, context)
            counted = parts.select(&:value)
            outlier = reference && Combine.outlier(counted,
                                                   @setup.quantity.outlier)
            kept = counted - [outlier]
            fused = Fused.new(location: name, quantity: @setup.quantity.name,
                              at:, value: nil, sigma: nil,
                              inside: inside(kept, reference), reference:,
                              corrected: !reference.nil?, parts: nil)
            outward(fused, Combine.shares(parts, kept, outlier), context)
        end

        # Weighted with a reference, the plain mean without.
        def inside(kept, reference)
            value, sigma = Combine.public_send(reference ? :weighted : :mean,
                                               kept)
            Estimate.new(value:, sigma:)
        end

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
