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
            # A Track's block when none is under way.
            NO_BLOCK = { block_sum: 0.0, block_noise: 0.0, block_count: 0,
                         block_at: nil }.freeze

            # sigma: what the drift is measured in, the Offset's σ in the
            # correction's space (Basis#corrected); nil for a reference.
            # share: what a block's mean innovation varies by, as a share
            # of one's (Offset#block_share); nil, 1: as much as one
            # innovation. width: the σ the part's innovations are judged
            # with at least, in place of the part's own when that is
            # narrower (a reference's, the location's tightest Offset σ,
            # in the correction's space too); nil: the part's own.
            def initialize(quantity, sigma, share = nil, width = nil)
                @quantity = quantity
                @sigma    = sigma
                @share    = share || 1.0
                @width    = width
            end

            # The track after the part's reading at `at`; others: the
            # other counted parts, their own deltas taken out (one alone:
            # no reading by itself is a jump, see settled). A block
            # that spans cusum_block by then is closed first: the reading
            # is measured against the delta it taught. A jumped track's
            # delta and variance are held as they were at the jump: its
            # innovations say whether the error is still away from them.
            def call(track, part, others, at)
                walked = track
                if walks?(track)
                    walked = track.with(variance: walked(track, at))
                end
                walked = closed(walked) if spans?(walked, at)
                innovation, noise = innovation(walked, part, others)
                z = innovation / Math.sqrt(walked.variance + noise)
                after = joined(walked, innovation, noise, at)
                settled(track, after, z, at, others.one?).with(at:)
            end

            private

            # The innovation y against the others' fusion, and its noise:
            # the part's σ² (the width at least) and the fusion's.
            def innovation(track, part, others)
                truth, spread, = Combine.robust(others, @quantity.robust_nu)
                [part.value - track.delta - truth,
                 (judged(part)**2) + (spread**2)]
            end

            def judged(part) = [part.sigma, @width || 0.0].max

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

            # Whether the random walk moves the variance: not a
            # reference's, nor a jumped track's.
            def walks?(track) = @sigma && track.state != :jumped

            # The block's mean innovation to the CUSUM standardised, then
            # to the Kalman step; no block under way after. Jumped, to
            # the return CUSUM alone.
            def closed(track)
                mean, noise = mean(track)
                total = track.variance + noise
                z = mean / Math.sqrt(total)
                return returning(track, z).with(**NO_BLOCK) if
                    track.state == :jumped
                moved(cusum(track, z), track.variance / total, mean)
                    .with(**NO_BLOCK)
            end

            # The block's mean innovation and its noise, share² of the
            # mean one's.
            def mean(track)
                count = track.block_count
                [track.block_sum / count,
                 (@share**2) * track.block_noise / count]
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

            # The return CUSUM of a jumped track, the jump's mirrored:
            # each side climbs by k less the block mean on its side, so
            # a side climbs while the error is back on that side of the
            # delta held, and stays down while it is still away. Each side
            # is held at h + k at most, so time away counts for no more
            # than one block of being back, and climbs by k at most, so a
            # block swung past the delta counts for no more than one back
            # at it: both past h, the error is within k of the delta held,
            # with the evidence a jump takes.
            def returning(track, z)
                k, h = @quantity.to_h.values_at(:cusum_k, :cusum_h)
                up = (track.cusum_up + k - z.clamp(0.0..)).clamp(0.0, h + k)
                down = (track.cusum_down + k + z.clamp(..0.0)).clamp(0.0, h + k)
                track.with(cusum_up: up, cusum_down: down)
            end

            # The track with its state: jumped once a CUSUM, the open
            # block counted for the share of a block it spans at `at`
            # (Track#level), is above cusum_h, or one innovation z beyond
            # cusum_h + cusum_k (a step a block would dilute) unless the
            # truth was a single other (lone): a truth of two others or
            # more doubts itself where they disagree (its σ widened, or
            # Student-t reweighted), so a reading that far from it is the
            # part's own; one other's reading has nothing to tell its
            # spike from the part's, and against it only a block's
            # evidence counts. The CUSUM is then restarted as the return
            # one (returning); back to ok once both sides of that are
            # above cusum_h (the error is back at the delta held, for as
            # long as the jump took to tell), the CUSUM restarted;
            # drifting past drift_alarm Offset σ, until back under
            # drift_clear (a reference, never).
            def settled(before, after, z, at, lone)
                if before.state == :jumped
                    return after.with(state: :jumped) unless back?(after)
                    return restarted(after, :ok)
                end
                return restarted(after, :jumped) if jumped?(after, z, at, lone)
                after.with(state: drift(before, after))
            end

            def restarted(track, state)
                track.with(state:, cusum_up: 0.0, cusum_down: 0.0)
            end

            def drift(before, after)
                return :ok unless @sigma
                bound = before.state == :drifting ? :drift_clear : :drift_alarm
                after.delta.abs > limit(bound) ? :drifting : :ok
            end

            def jumped?(track, z, at, lone)
                k, h = @quantity.to_h.values_at(:cusum_k, :cusum_h)
                track.level(k, track.spanned(block, at)) > h ||
                    (!lone && z.abs > h + k)
            end

            def back?(track)
                h = @quantity.cusum_h
                track.cusum_up > h && track.cusum_down > h
            end

            def limit(bound) = @quantity.public_send(bound) * @sigma
        end
    end
end
