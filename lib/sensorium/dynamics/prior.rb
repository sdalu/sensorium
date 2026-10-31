# frozen_string_literal: true

module Sensorium
    module Dynamics
        # What the caller knows of a location's dynamics before its
        # history says anything: a, c ([mean, σ], per bin) and b
        # ({ name => [mean, σ] }), any of them nil when nothing is
        # known. A time constant τ (hours) is a = bin / (τ × 3600). The
        # fit adds each prior's precision to the data's, as a Gaussian
        # prior: a loose one gives way to plentiful data, a tight one
        # holds where data is thin. Where it comes from (a building's
        # walls, another room, a past year) is the caller's.
        Prior = Data.define(:a, :b, :c) do
            def initialize(a: nil, b: nil, c: nil)
                b = (b || {}).transform_keys(&:to_s)
                [a, c, *b.values].each { check(it) }
                super
            end

            # [mean, σ] or nil, for each column of a fit: the gap's (a),
            # each Switch's (b), the constant's (c).
            def columns(gap, names)
                [*([a] if gap), *names.map { b[it] }, c]
            end

            private

            def check(pair)
                return unless pair
                _, sigma = pair
                return if sigma.is_a?(Numeric) && sigma.finite? &&
                          sigma.positive?
                raise ArgumentError, "a Prior's σ must be finite and positive"
            end
        end
    end
end
