# frozen_string_literal: true

module Sensorium
    module Dynamics
        # Whether a location's model in a regime predicts better than
        # holding the last value: fitted without the last tenth of its
        # steps (a week of them at least), it must predict the reference
        # two hours ahead from those steps' bins, as the Fusion does,
        # with an RMS error at most Setup#dynamics_margin (0.98) of
        # holding's: margins of a few thousandths are noise (a model that
        # won in May by 0.7 % lost in October). Kept, it is fitted again
        # on all the steps, with both errors.
        module Validation
            module_function

            HOURS = 2
            SHARE = 0.1
            LEAST = 7 * 86_400

            # The Model, nil when refused.
            def model(key, steps, setup, forecast, prior = nil)
                sorted = steps.sort_by(&:bin)
                rms = held_out(key, sorted, setup, forecast, prior) or return
                return unless wins?(rms, setup)
                Regression.model(key, sorted, setup, forecast, prior)
                          &.with(rms_model: rms.first, rms_hold: rms.last)
            end

            # [rms_model, rms_hold] on the steps held out, by the model
            # fitted on the others; nil when it cannot be told.
            def held_out(key, sorted, setup, forecast, prior)
                held = held(sorted.size, setup.bin)
                return if held >= sorted.size
                fitted = Regression.model(key, sorted[0...-held], setup,
                                          forecast, prior) or return
                forecast.rms(fitted, sorted.last(held).map(&:bin), HOURS)
            end

            # Whether [rms_model, rms_hold] beats holding by the setup's
            # margin: the model's error at most that share of holding's.
            def wins?(rms, setup)
                rms.first <= setup.dynamics_margin * rms.last
            end

            # How many of the last steps are held out.
            def held(size, bin) = [(size * SHARE).ceil, LEAST / bin].max
        end
    end
end
