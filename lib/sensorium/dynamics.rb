# frozen_string_literal: true

module Sensorium
    # How a location's reference r moves on its own, per regime: a
    # first-order discrete model over one bin,
    #   r(t + bin) - r(t) = a × (outside - r) + Σ b[name] × on[name] + c
    #                       + noise
    # outside the external series Setup#outside names (none: a is 0),
    # on[name] 1 while that Switch is on (its hard hold), else 0. Fitted
    # by least squares over the bins where every term is known and no
    # Mode held (nor within its hold), on the reference's carried
    # series, as the History finds it. q is the mean square of the
    # error of predicting an hour ahead (as the Fusion does) over the
    # bins fitted, per hour. The Fusion moves an aged reading by the
    # change the model predicts over its age, and grows its σ² by
    # q × its age (hours). A model is kept only when, fitted without
    # the last tenth of its bins (a week at least), it predicts those
    # two hours ahead better than holding the last value (Validation).
    module Dynamics
        # A location's model in a regime: a, c per bin; b { name => per
        # bin }; q per hour; bin, seconds; steps, how many it was
        # fitted on; rms_hold, rms_model, the RMS error two hours ahead
        # on the bins held out, holding the last value and by the
        # model fitted without them.
        Model = Data.define(:location, :quantity, :regime, :a, :b, :c, :q,
                            :bin, :steps, :rms_hold, :rms_model) do
            def initialize(b: {}, rms_hold: nil, rms_model: nil, **)
                super(b: b.transform_keys(&:to_s), rms_hold:, rms_model:,
                      **)
            end

            # Whether the change needs the outside's value.
            def outside? = !a.zero?

            # The change predicted over `hours` from value, the outside
            # at `outside` (nil: unknown), the Switches named in `on` on:
            # the model stepped over that many bins, in closed form, an
            # approach to the equilibrium the inputs hold the room at.
            def change(value, outside, on, hours)
                return if outside? && outside.nil?
                bins = hours * 3600.0 / bin
                drive = switched(on) + c
                return drive * bins unless outside?
                (outside + (drive / a) - value) * approached(bins)
            end

            # The share of the way to equilibrium covered in `bins`.
            def approached(bins) = 1 - ((1 - a)**bins)

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
        # (setup.min_samples steps), stable (a not negative) and
        # validated.
        # span: from:, to: and locations: ({ name => Location }, those
        # set), the History loaded from the source when none is given.
        # priors: { location => Prior }, or anything answering
        # call(location, regime) with one or nil.
        def learn(source, setup, history: nil, priors: {}, **span)
            history = Sensorium::History.given(history, source, setup, span)
            History.new(history, priors:).models
        end
    end
end

require_relative "dynamics/history"
require_relative "dynamics/regression"
require_relative "dynamics/forecast"
require_relative "dynamics/validation"
require_relative "dynamics/prior"
require_relative "dynamics/weighting"
