# frozen_string_literal: true

module Sensorium
    # How a location's reference r moves on its own, per regime: a
    # first-order discrete model over one bin,
    #   r(t + bin) - r(t) = a × (outside - r) + Σ b[name] × on[name] + c
    #                       + noise
    # outside the external series Setup#outside names (none: a is 0),
    # on[name] 1 while that Switch is on (its hard hold), else 0. Fitted
    # by least squares over the bins where every term is known, on the
    # reference's carried series, as the Learner builds it. q is the
    # variance of what the model leaves, per hour. The Fusion moves an
    # aged reading by the change the model predicts over its age, and
    # grows its σ² by q × its age (hours).
    module Dynamics
        # A location's model in a regime: a, c per bin; b { name => per
        # bin }; q per hour; bin, seconds; steps, how many it was
        # fitted on.
        Model = Data.define(:location, :quantity, :regime, :a, :b, :c, :q,
                            :bin, :steps) do
            def initialize(b: {}, **)
                super(b: b.transform_keys(&:to_s), **)
            end

            # Whether the change needs the outside's value.
            def outside? = !a.zero?

            # The change predicted over `hours` from value, the outside
            # at `outside` (nil: unknown), the Switches named in `on` on.
            def change(value, outside, on, hours)
                return if outside? && outside.nil?
                per_bin = (a * (outside.to_f - value)) + switched(on) + c
                per_bin * hours * 3600 / bin
            end

            # Σ b of the Switches named in `on`.
            def switched(on)
                names = on.map(&:to_s)
                b.sum { |name, term| names.include?(name) ? term : 0 }
            end

            # The variance the model's noise adds over `hours`.
            def variance(hours) = q * hours
        end

        module_function

        # [Model] of each location with a reference (as the Learner finds
        # it), in each regime of the span seen often enough
        # (setup.min_samples steps) and stable (a not negative).
        # locations: { name => Location }, those set.
        def learn(source, setup, from:, to:, locations: {})
            History.new(source, setup, from, to, locations).models
        end
    end
end

require_relative "dynamics/history"
require_relative "dynamics/regression"
