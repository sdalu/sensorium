# frozen_string_literal: true

module Sensorium
    # Where a quantity is learned and fused: a space where a sensor's
    # error adds up. forward(value, context) takes a reading there (nil
    # when its context lacks what it needs), inverse(value, context)
    # brings a fused value back, sigma(σ, inside, outside) brings its σ.
    module Transform
        # The quantity as it reads (temperature).
        module Identity
            module_function

            def forward(value, _context = {})      = value
            def inverse(value, _context = {})      = value
            def sigma(sigma, _inside, _outside)    = sigma
        end

        # Relative humidity (%) fused as absolute humidity (g/m³): a
        # sensor 1 °C warmer than the room reads about 6 % lower for the
        # same air. Each reading goes in with its own sensor's
        # temperature, the fused value comes back at the location's
        # (context[:temperature], °C). Magnus formula over water.
        module AbsoluteHumidity
            module_function

            def forward(value, context = {})
                t = context[:temperature] or return
                value * saturation(t) / 100.0
            end

            def inverse(value, context = {})
                t = context[:temperature] or return
                100.0 * value / saturation(t)
            end

            def sigma(sigma, inside, outside)
                return unless sigma && outside
                inside.zero? ? sigma : sigma * outside / inside
            end

            # g/m³ of water vapour at saturation, at t °C.
            def saturation(t)
                hpa = 6.112 * Math.exp(17.67 * t / (t + 243.5))
                hpa * 216.74 / (273.15 + t)
            end
        end
    end
end
