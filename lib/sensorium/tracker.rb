# frozen_string_literal: true

module Sensorium
    # What the Tracker knows of one sensor's offset between two
    # learnings, for one quantity: delta, the sensor's corrected value
    # minus the truth, estimated, and its variance; the two sides of the
    # CUSUM on its innovations' block means (jumped, of the return CUSUM,
    # Tracker::Step#returning); the block under way, the
    # sum of its innovations, of their noise (the part's σ² and the
    # fusion's), their count, and the time of its first reading
    # (block_at, nil before any); at, the time of the
    # reading its last update took (none is taken twice); state,
    # :ok, :drifting or :jumped. regime, reference, constant and plain
    # are the fingerprint of the Offset it tracks: once the location's
    # Offset for the device has another (a relearn), the track starts
    # afresh. A reference's track has no Offset: constant and plain nil,
    # reference the location's references ("a+b").
    Track = Data.define(:location, :device, :quantity, :regime, :reference,
                        :constant, :plain, :delta, :variance, :cusum_up,
                        :cusum_down, :block_sum, :block_noise,
                        :block_count, :block_at, :at, :state) do
        def initialize(block_sum: 0.0, block_noise: 0.0, block_count: 0,
                       block_at: nil, **)
            super
        end

        def fingerprint = [regime, reference, constant, plain]

        # The higher side of the CUSUM, with the block under way counted
        # as if it closed now, its mean taken to vary as one innovation
        # (a mean of positively correlated innovations varies no more),
        # for the share of a block it spans (spanned, 0..1): its
        # readings are correlated with the block just closed, so a block
        # of minutes adds little the CUSUM has not seen, and a step far
        # beyond the noise is still seen before its block closes.
        def level(slack, spanned = 1.0)
            open = opened
            [cusum_up, cusum_down, cusum_up + (spanned * (open - slack)),
             cusum_down + (spanned * (-open - slack))].max
        end

        # The share of a block of `block` seconds the block under way
        # spans at `at`, 0..1; 0 without one.
        def spanned(block, at)
            return 0.0 unless block_at
            [(at - block_at) / block.to_f, 1.0].min
        end

        # The block under way's mean innovation, standardised as one
        # innovation; 0 before any.
        def opened
            return 0.0 unless block_count.positive?
            mean = block_sum / block_count
            mean / Math.sqrt(variance + (block_noise / block_count))
        end

        # Whether the track is a reference's, pinned: its delta 0 by
        # convention, never estimated (Tracker::Step).
        def pinned? = constant.nil?

        # A Parts::Part that counts, as the Fusion takes it: delta taken
        # out, variance, how far delta may be off, added to its σ²; a
        # pinned track's delta is no estimate, and adds nothing. When
        # jumped, it does not count, when drifting, it is noted.
        def apply(part)
            return part.with(value: nil, sigma: nil, note: "jumped") if
                state == :jumped
            part.with(value: part.value - delta, sigma: widened(part.sigma),
                      note: ("drifting" if state == :drifting))
        end

        def widened(sigma)
            pinned? ? sigma : Math.sqrt((sigma**2) + variance)
        end
    end

    class Track
        STATES = %i[ok drifting jumped].freeze

        def self.fingerprint(offset)
            [offset.regime, offset.reference, offset.constant, offset.plain]
        end

        # A reference's: references, the location's ("a+b").
        def self.reference(regime, references) = [regime, references, nil, nil]

        # A track of the offset as it starts: delta 0, with that variance.
        def self.fresh(offset, variance)
            start(**offset.to_h.slice(:location, :device, :quantity, :regime,
                                      :reference, :constant, :plain),
                  variance:)
        end

        # A track as it starts, of what the keywords say.
        def self.start(constant: nil, plain: nil, **)
            new(constant:, plain:, delta: 0.0, cusum_up: 0.0,
                cusum_down: 0.0, at: nil, state: :ok, **)
        end
    end

    # Follows each sensor's offset between two learnings: a scalar Kalman
    # filter on delta, a random walk over the batch-learned Offset, fed
    # by the innovation of each part against the others' fusion, and a
    # two-sided CUSUM on the standardised innovations to tell a jump
    # from a drift. Tracks are { [location, device] => Track }, those of
    # one quantity; update and reset give new ones.
    class Tracker
        # The Fused parts that count: a value and a σ, no note but
        # "outlier".
        COUNTING = [nil, "outlier"].freeze

        # The share of cusum_h past which the part with the highest
        # CUSUM is the suspect, left out of the others' truth until its
        # CUSUM falls back or it jumps.
        SUSPECT = 0.5

        # The keywords a Tracker may take instead of a Knowledge.
        REQUIRED = %i[offsets].freeze
        OPTIONAL = %i[locations transients].freeze

        # knowledge: a Knowledge of the setup's quantity: its offsets, as
        # the Fusion's; its transients and locations (those set, for
        # their max_age), for the Detector. Or, instead, those as
        # keywords, offsets: required.
        def initialize(setup, knowledge: nil, **given)
            knowledge = Knowledge.given(knowledge, given, REQUIRED, OPTIONAL)
            @setup    = setup
            @quantity = setup.quantity
            @offsets  = knowledge.offsets.to_h do |offset|
                [[offset.location, offset.regime, offset.device], offset]
            end
            @detector = Transient::Detector.new(setup, knowledge:)
        end

        # The tracks after a Fused, made with tracks or without, each
        # part taken as it was before its Track (Weighted#untracked):
        # each part that counts, a reference or with an Offset, updated
        # against the others, the references first. A part is left out
        # of the others while its track has jumped, or once it jumped in
        # this update. The suspect (suspect), the part whose CUSUM is the
        # highest once past SUSPECT of cusum_h, of three that count or
        # more, is left out of the others of every other part: a step
        # not yet flagged leaks into no other's delta. A sensor whose
        # single other is a reference is updated against it alone
        # (told?). A part with fewer others is left as it was, as is
        # one whose reading is no newer than its track's last (a Fused
        # made again before the sensor read again), and the tracks of
        # other parts. While the Detector finds an event in the
        # location in snapshot (the one fused was made from), every
        # part is left as it was.
        def update(tracks, fused, snapshot: nil)
            return tracks if transient?(fused, snapshot)
            counted = fused.parts.select { counts?(it) }.map(&:untracked)
            current = current(tracks, fused, counted)
            out = current.filter_map do |device, (track, _)|
                device if track.state == :jumped
            end
            flagged = [out, suspect(current)]
            tracks.merge(updated(fused, counted, current, flagged))
        end

        # The tracks without that sensor's: its next update starts afresh.
        def reset(tracks, location, device) = tracks.except([location, device])

        private

        # The device whose CUSUM (Track#level, the block under way
        # counted in full: a suspect is left out, not flagged, and is
        # back once its CUSUM falls) is the highest, once past SUSPECT
        # of cusum_h, of those not jumped, when they are three or more:
        # with two, no majority tells which is off, and neither is
        # suspect; nil without.
        def suspect(current)
            k, h = @quantity.to_h.values_at(:cusum_k, :cusum_h)
            levels = current.filter_map do |device, (track, _)|
                [device, track.level(k)] unless track.state == :jumped
            end
            return if levels.size < 3
            device, level = levels.max_by(&:last)
            device if level && level > SUSPECT * h
        end

        # Whether a transient is under way in the Fused's location.
        def transient?(fused, snapshot)
            return false unless snapshot
            @detector.events(snapshot).any? do |event|
                event.location == fused.location
            end
        end

        # { [location, device] => Track } updated, the references first,
        # in the Fused's order; flagged: [the devices jumped, those that
        # jump added; the suspect].
        def updated(fused, counted, current, flagged)
            out, suspect = flagged
            ordered(fused, counted).each_with_object({}) do |part, done|
                left = part.device == suspect ? out : out + [suspect]
                others = others_of(part, counted, current, left)
                track = step(fused, current, part, others) or next
                out << part.device if track.state == :jumped
                done[[fused.location, part.device]] = track
            end
        end

        # The counted parts but the part and those left, their own
        # deltas taken out.
        def others_of(part, counted, current, left)
            others(counted.reject { left.include?(it.device) } - [part],
                   current)
        end

        # The references first, then the other parts, each in the Fused's
        # order.
        def ordered(fused, parts)
            references = references_of(fused)
            parts.partition { references.include?(it.device) }.flatten
        end

        def references_of(fused)
            name = fused.reference or return []
            Sensorium.references_of(name)
        end

        # The part's track updated; nil without one, when the others
        # (their deltas taken out) tell it no truth (told?), or when its
        # reading is no newer than the track's last.
        def step(fused, current, part, others)
            track, sigma, share, width = current[part.device]
            return unless track && told?(fused, part, others)
            return if track.at && part.time <= track.at
            Step.new(@quantity, sigma, share, width)
                .call(track, part, others, part.time)
        end

        # Whether the others tell the part's truth: two or more, whose
        # fusion it is; or, for a sensor, a reference alone, the anchor
        # its Offset was learned against. A disagreement between two
        # sensors, or two references, cannot be put on either side.
        def told?(fused, part, others)
            return true if others.size >= 2
            return false unless others.one?
            references = references_of(fused)
            references.include?(others.first.device) &&
                !references.include?(part.device)
        end

        # Whether the part, untracked, counts: its note the Part's when a
        # Track was applied to it, the Weighted's otherwise.
        def counts?(weighted)
            part = weighted.untracked
            note = weighted.tracked? ? part.note : weighted.note
            part.value && part.sigma && COUNTING.include?(note)
        end

        # The others, each with its own delta taken out.
        def others(parts, current)
            parts.map do |part|
                track, = current[part.device]
                part.with(value: part.value - (track&.delta || 0.0))
            end
        end
    end
end

require_relative "tracker/basis"
require_relative "tracker/step"
