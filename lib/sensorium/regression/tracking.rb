# frozen_string_literal: true

module Sensorium
    class Regression
        # Following a Regression between two learnings, as the Tracker
        # follows an Offset (Tracker::Step): each value observed is an
        # innovation against the value predicted, delta, a random walk
        # over the learned model, is what the value runs above it now,
        # and a CUSUM on block means tells a jump (a boiler that burns
        # more for the same valves since a date) from a drift. The Track
        # is a Regression's: location nil, device its name, reference
        # nil; it starts afresh once the Regression is learned again
        # (another constant or plain median) or in another regime.
        module Tracking
            # The Track after the value observed at `at`, the regressors'
            # values then (values: as predict takes them): track, the
            # one so far (nil: a fresh one). quantity: the Quantity, its
            # σ the observation's own error, its track_q, cusum_block,
            # cusum_k, cusum_h, drift_alarm and drift_clear the
            # Tracker's.
            def follow(track, observed:, values:, at:, quantity:)
                track = fresh(quantity) unless track&.fingerprint ==
                                               fingerprint
                part = Estimate.new(value: observed, sigma: quantity.sigma)
                Tracker::Step.new(quantity, sigma, block_share)
                             .call(track, part, [predict(values)], at)
            end

            # What a Track of this Regression carries (Track#fingerprint).
            def fingerprint = [regime, nil, constant, plain]

            private

            def fresh(quantity)
                Track.start(location: nil, device: name,
                            quantity: quantity.name, regime:, reference: nil,
                            constant:, plain:,
                            variance: (quantity.sigma / 2.0)**2)
            end
        end

        include Tracking
    end
end
