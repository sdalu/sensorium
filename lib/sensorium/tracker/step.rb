# frozen_string_literal: true

module Sensorium
    class Tracker
        # One update of a Track against the others' fusion. Each reading
        # walks the variance and joins the block under way; once the
        # block spans cusum_block, its mean innovation is standardised
        # and fed to the CUSUM, then taken by the Kalman step: the
        # innovations of a sensor whose error persists for hours are not
        # independent, and a block is what is. A reference's track is
        # pinned: neither its delta nor its variance moves, and it never
        # drifts; only its CUSUM runs, and it may jump.
        class Step
            # sigma: what the drift is measured in, the Offset's; nil for
            # a reference. share: what a block's mean innovation varies
            # by, as a share of one's (Offset#block_share); nil, 1: as
            # much as one innovation.
            def initialize(quantity, sigma, share = nil)
                @quantity = quantity
                @sigma    = sigma
                @share    = share || 1.0
            end

            # The track after the part's reading at `at`; others: the
            # other counted parts, their own deltas taken out. A block
            # that spans cusum_block by then is closed first: the reading
            # is measured against the delta it taught.
            def call(track, part, others, at)
                walked = track
                walked = track.with(variance: walked(track, at)) if @sigma
                walked = closed(walked) if spans?(walked, at)
                innovation, noise = innovation(walked, part, others)
                z = innovation / Math.sqrt(walked.variance + noise)
                after = joined(walked, innovation, noise, at)
                after.with(at:, state: state(track, after, z))
            end

            private

            # The innovation y against the others' fusion, and its noise:
            # the part's σ² and the fusion's.
            def innovation(track, part, others)
                truth, spread, = Combine.robust(others, @quantity.robust_nu)
                [part.value - track.delta - truth,
                 (part.sigma**2) + (spread**2)]
            end

            # The variance grown by the random walk since the last reading.
            def walked(track, at)
                track.variance + (@quantity.track_q * hours(track, at))
            end

            def hours(track, at)
                track.at ? [at - track.at, 0].max / 3600.0 : 0.0
            end

            # Whether the block under way spans cusum_block at `at`.
            def spans?(track, at)
                track.block_at && at - track.block_at >= block
            end

            # The innovation added to the block under way, the first of
            # one when none is.
            def joined(track, innovation, noise, at)
                track.with(block_sum: track.block_sum + innovation,
                           block_noise: track.block_noise + noise,
                           block_count: track.block_count + 1,
                           block_at: track.block_at || at)
            end

            def block = @quantity.cusum_block

            # The block's mean innovation, its noise share² of the mean
            # one's, to the CUSUM standardised, then to the Kalman step;
            # no block under way after.
            def closed(track)
                mean = track.block_sum / track.block_count
                noise = (@share**2) * track.block_noise / track.block_count
                total = track.variance + noise
                moved(cusum(track, mean / Math.sqrt(total)),
                      track.variance / total, mean)
                    .with(block_sum: 0.0, block_noise: 0.0, block_count: 0,
                          block_at: nil)
            end

            def moved(track, gain, innovation)
                return track unless @sigma
                track.with(delta: track.delta + (gain * innovation),
                           variance: track.variance * (1 - gain))
            end

            def cusum(track, z)
                k = @quantity.cusum_k
                track.with(cusum_up: [0.0, track.cusum_up + z - k].max,
                           cusum_down: [0.0, track.cusum_down - z - k].max)
            end

            # Jumped once a CUSUM, the open block counted (Track#level),
            # is above cusum_h, or one innovation z beyond cusum_h +
            # cusum_k (a step a block would dilute), until a relearn or
            # a reset; drifting past drift_alarm Offset σ, until back
            # under drift_clear (a reference, never).
            def state(before, after, z)
                return :jumped if before.state == :jumped ||
                                  jumped?(after, z)
                return :ok unless @sigma
                bound = before.state == :drifting ? :drift_clear : :drift_alarm
                return :drifting if after.delta.abs > limit(bound)
                :ok
            end

            def jumped?(track, z)
                k, h = @quantity.to_h.values_at(:cusum_k, :cusum_h)
                track.level(k) > h || z.abs > h + k
            end

            def limit(bound) = @quantity.public_send(bound) * @sigma
        end
    end
end
