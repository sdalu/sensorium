# frozen_string_literal: true

module Sensorium
    # What the Tracker knows of one sensor's offset between two
    # learnings, for one quantity: delta, the sensor's corrected value
    # minus the truth, estimated, and its variance; the two sides of the
    # CUSUM on its innovations; at, the time of its last update; state,
    # :ok, :drifting or :jumped. regime, reference, constant and plain
    # are the fingerprint of the Offset it tracks: once the location's
    # Offset for the device has another (a relearn), the track starts
    # afresh.
    Track = Data.define(:location, :device, :quantity, :regime, :reference,
                        :constant, :plain, :delta, :variance, :cusum_up,
                        :cusum_down, :at, :state) do
        def fingerprint = [regime, reference, constant, plain]

        # Whether it tracks that Offset (nil: none).
        def tracks?(offset)
            !offset.nil? && fingerprint == Track.fingerprint(offset)
        end

        # A Parts::Part that counts, as the Fusion takes it: delta taken
        # out, variance added to its σ²; when jumped, it does not count,
        # when drifting, it is noted.
        def apply(part)
            return part.with(value: nil, sigma: nil, note: "jumped") if
                state == :jumped
            part.with(value: part.value - delta,
                      sigma: Math.sqrt((part.sigma**2) + variance),
                      note: ("drifting" if state == :drifting))
        end
    end

    class Track
        STATES = %i[ok drifting jumped].freeze

        def self.fingerprint(offset)
            [offset.regime, offset.reference, offset.constant, offset.plain]
        end

        # A track of the offset as it starts: delta 0, with that variance.
        def self.fresh(offset, variance)
            new(location: offset.location, device: offset.device,
                quantity: offset.quantity, regime: offset.regime,
                reference: offset.reference, constant: offset.constant,
                plain: offset.plain, delta: 0.0, variance:, cusum_up: 0.0,
                cusum_down: 0.0, at: nil, state: :ok)
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

        # offsets: [Offset] of the setup's quantity, as the Fusion's.
        def initialize(setup, offsets:)
            @setup    = setup
            @quantity = setup.quantity
            @offsets  = offsets.to_h do |offset|
                [[offset.location, offset.regime, offset.device], offset]
            end
        end

        # The tracks after a Fused, made by a Fusion without tracks: each
        # part that counts, with an Offset and two others or more that
        # count, updated against them; the others left as they were.
        def update(tracks, fused)
            counted = fused.parts.select { counts?(it) }.map(&:part)
            current = current(tracks, fused, counted)
            tracks.merge(counted.filter_map do |part|
                updated = step(fused, current, part, counted - [part]) or next
                [[fused.location, part.device], updated]
            end.to_h)
        end

        # The tracks without that sensor's: its next update starts afresh.
        def reset(tracks, location, device)
            tracks.except([location, device])
        end

        private

        # The part's track updated; nil without one, or with fewer than
        # two others.
        def step(fused, current, part, others)
            track = current[part.device]
            return unless track && others.size >= 2
            Step.new(@quantity, offset(fused, part.device))
                .call(track, part, others(others, current), fused.at)
        end

        def counts?(weighted)
            weighted.part.value && weighted.part.sigma &&
                COUNTING.include?(weighted.note)
        end

        # { device => Track } of the parts with an Offset: theirs while it
        # tracks the Offset, else a fresh one.
        def current(tracks, fused, parts)
            parts.filter_map do |part|
                offset = offset(fused, part.device) or next
                track = tracks[[fused.location, part.device]]
                track = fresh(offset) unless track&.tracks?(offset)
                [part.device, track]
            end.to_h
        end

        # The location's Offset for the device in the moment's regime,
        # learned against the Fused's reference.
        def offset(fused, device)
            key = [fused.location, @setup.regime.of(fused.at), device]
            offset = @offsets[key]
            offset if offset&.reference == fused.reference
        end

        def fresh(offset) = Track.fresh(offset, (@quantity.sigma / 2.0)**2)

        # The others, each with its own delta taken out.
        def others(parts, current)
            parts.map do |part|
                part.with(value: part.value - (current[part.device]&.delta ||
                                               0.0))
            end
        end
    end
end

require_relative "tracker/step"
