# frozen_string_literal: true

module Sensorium
    # What the Tracker knows of one sensor's offset between two
    # learnings, for one quantity: delta, the sensor's corrected value
    # minus the truth, estimated, and its variance; the two sides of the
    # CUSUM on its innovations; at, the time of its last update; state,
    # :ok, :drifting or :jumped. regime, reference, constant and plain
    # are the fingerprint of the Offset it tracks: once the location's
    # Offset for the device has another (a relearn), the track starts
    # afresh. A reference's track has no Offset: constant and plain nil,
    # reference the location's references ("a+b").
    Track = Data.define(:location, :device, :quantity, :regime, :reference,
                        :constant, :plain, :delta, :variance, :cusum_up,
                        :cusum_down, :at, :state) do
        def fingerprint = [regime, reference, constant, plain]

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

        # offsets: [Offset] of the setup's quantity, as the Fusion's;
        # dynamics: [Dynamics::Model] and locations: { name => Location
        # }, those set, for the witness (Witness); transients:
        # [Transient::Profile], for the Detector.
        def initialize(setup, offsets:, dynamics: [], locations: {},
                       transients: [])
            @setup    = setup
            @quantity = setup.quantity
            @offsets  = offsets.to_h do |offset|
                [[offset.location, offset.regime, offset.device], offset]
            end
            @witness = Witness.new(setup, dynamics, locations)
            @detector = Transient::Detector.new(setup, profiles: transients,
                                                       locations:)
        end

        # The tracks after a Fused, made by a Fusion without tracks: each
        # part that counts, a reference or with an Offset, updated
        # against the others, the references first. A part is left out
        # of the others while its track has jumped, or once it jumped in
        # this update. A part with a single other takes, as a second,
        # the witness: previous (a Fused of the location made with the
        # tracks) moved by the location's dynamics to the moment, with
        # the inputs of snapshot (the one fused was made from). A part
        # with fewer than two others still is left as it was, as are
        # the tracks of other parts. While the Detector finds an event in
        # the location in snapshot, every part is left as it was.
        def update(tracks, fused, previous: nil, snapshot: nil)
            return tracks if transient?(fused, snapshot)
            counted = fused.parts.select { counts?(it) }.map(&:part)
            current = current(tracks, fused, counted)
            out = current.filter_map do |device, (track, _)|
                device if track.state == :jumped
            end
            witness = @witness.of(fused, previous, snapshot)
            tracks.merge(updated(fused, counted, current, out, witness))
        end

        # The tracks without that sensor's: its next update starts afresh.
        def reset(tracks, location, device)
            tracks.except([location, device])
        end

        private

        # Whether a transient is under way in the Fused's location.
        def transient?(fused, snapshot)
            return false unless snapshot
            @detector.events(snapshot).any? do |event|
                event.location == fused.location
            end
        end

        # { [location, device] => Track } updated, the references first,
        # in the Fused's order; out: the devices left out of the others,
        # those that jump added; witness: an Estimate or nil.
        def updated(fused, counted, current, out, witness)
            ordered(fused, counted).each_with_object({}) do |part, done|
                others = others(counted.reject { out.include?(it.device) } -
                                [part], current)
                track = step(fused, current, part,
                             witnessed(others, witness)) or next
                out << part.device if track.state == :jumped
                done[[fused.location, part.device]] = track
            end
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

        # The others, and the witness when they are one.
        def witnessed(others, witness)
            witness && others.one? ? others + [witness] : others
        end

        # The part's track updated; nil without one, or with fewer than
        # two others (their deltas taken out).
        def step(fused, current, part, others)
            track, sigma = current[part.device]
            return unless track && others.size >= 2
            Step.new(@quantity, sigma).call(track, part, others, fused.at)
        end

        def counts?(weighted)
            weighted.part.value && weighted.part.sigma &&
                COUNTING.include?(weighted.note)
        end

        # { device => [Track, σ] } of the parts tracked: theirs while it
        # has the fingerprint of the moment, else a fresh one; σ, what
        # their drift is measured in, nil for a reference.
        def current(tracks, fused, parts)
            parts.filter_map do |part|
                found = basis(fused, part.device) or next
                fresh, sigma = found
                track = tracks[[fused.location, part.device]]
                track = fresh unless track&.fingerprint == fresh.fingerprint
                [part.device, [track, sigma]]
            end.to_h
        end

        # A fresh Track of the device and the σ its drift is measured in:
        # a reference's, without (it never drifts); another's, of its
        # Offset learned against the Fused's references, with its σ; nil
        # without.
        def basis(fused, device)
            if references_of(fused).include?(device)
                [reference(fused, device), nil]
            elsif (offset = offset(fused, device))
                [Track.fresh(offset, variance), offset.sigma]
            end
        end

        def reference(fused, device)
            Track.start(location: fused.location, device:,
                        quantity: fused.quantity, regime: regime(fused),
                        reference: fused.reference, variance:)
        end

        def offset(fused, device)
            offset = @offsets[[fused.location, regime(fused), device]]
            offset if offset&.reference == fused.reference
        end

        def regime(fused) = @setup.regime.of(fused.at)

        # A fresh track's: (σ/2)², σ the quantity's.
        def variance = (@quantity.sigma / 2.0)**2

        # The others, each with its own delta taken out.
        def others(parts, current)
            parts.map do |part|
                track, = current[part.device]
                part.with(value: part.value - (track&.delta || 0.0))
            end
        end
    end
end

require_relative "tracker/step"
require_relative "tracker/witness"
