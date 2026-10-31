# frozen_string_literal: true

module Sensorium
    class Tracker
        # One update of a Track against the others' fusion: the random
        # walk, the Kalman step, the CUSUM and the state. A reference's
        # track is pinned: neither its delta nor its variance moves, and
        # it never drifts; only its CUSUM runs, and it may jump.
        class Step
            # sigma: what the drift is measured in, the Offset's; nil for
            # a reference.
            def initialize(quantity, sigma)
                @quantity = quantity
                @sigma    = sigma
            end

            # The track after the part's reading at `at`; others: the
            # other counted parts, their own deltas taken out.
            def call(track, part, others, at)
                prior = @sigma ? walked(track, at) : track.variance
                innovation, total = innovation(track, part, others, prior)
                after = cusum(moved(track, prior / total, innovation, prior),
                              innovation / Math.sqrt(total))
                after.with(at:, state: state(track, after))
            end

            private

            # The innovation y against the others' fusion, and its
            # variance: the prior's, the part's σ² and the fusion's.
            def innovation(track, part, others, prior)
                truth, spread, = Combine.robust(others, @quantity.robust_nu)
                [part.value - track.delta - truth,
                 prior + (part.sigma**2) + (spread**2)]
            end

            # The variance grown by the random walk since the last update.
            def walked(track, at)
                track.variance + (@quantity.track_q * hours(track, at))
            end

            def hours(track, at)
                track.at ? [at - track.at, 0].max / 3600.0 : 0.0
            end

            def moved(track, gain, innovation, prior)
                return track unless @sigma
                track.with(delta: track.delta + (gain * innovation),
                           variance: prior * (1 - gain))
            end

            def cusum(track, z)
                k = @quantity.cusum_k
                track.with(cusum_up: [0.0, track.cusum_up + z - k].max,
                           cusum_down: [0.0, track.cusum_down - z - k].max)
            end

            # Jumped once a CUSUM is above cusum_h, until a relearn or a
            # reset; drifting past drift_alarm Offset σ, until back
            # under drift_clear (a reference, never).
            def state(before, after)
                return :jumped if before.state == :jumped || jumped?(after)
                return :ok unless @sigma
                bound = before.state == :drifting ? :drift_clear : :drift_alarm
                return :drifting if after.delta.abs > limit(bound)
                :ok
            end

            def jumped?(track)
                [track.cusum_up, track.cusum_down].max > @quantity.cusum_h
            end

            def limit(bound) = @quantity.public_send(bound) * @sigma
        end
    end
end
