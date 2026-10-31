# frozen_string_literal: true

module Sensorium
    # A location's value, fused from all its sensors: each corrected to
    # the location's reference (Parts), weighted by 1/σ², σ grown with
    # the reading's age, then Student-t reweighted (Combine.robust): a
    # sensor far from what the others say (sun on it, a window open by
    # it) keeps only a little weight, and is noted "outlier".
    # A location without a reference gets the plain mean, corrected
    # false and sigma nil. The offsets are those of the moment's regime.
    # The value is brought back from the transform's space with the
    # context given (a humidity at the location's fused temperature).
    class Fusion
        # value, sigma: as the quantity reads (nil when the transform
        # cannot bring them back); inside: an Estimate in the transform's
        # space; parts: [Weighted].
        Fused = Data.define(:location, :quantity, :at, :value, :sigma,
                            :inside, :reference, :corrected, :parts)
        # A Part, its share of the value (0..1), why it is left out, and
        # its value brought back as the quantity reads.
        Weighted = Data.define(:part, :weight, :note, :value)

        # offsets: [Offset]; shifts: [Shift]; locations: { name =>
        # Location }, those set; tracks: { [location, device] => Track },
        # the Tracker's; all of the setup's quantity.
        def initialize(setup, offsets:, shifts:, locations: {}, tracks: {})
            @setup     = setup
            @offsets   = offsets.group_by { [it.location, it.regime] }
            @shifts    = shifts.group_by { [it.location, it.regime] }
            @locations = locations
            @tracks    = tracks
        end

        # The locations it can tell: those learned, set, or read.
        def locations(snapshot)
            (@offsets.keys.map(&:first) + @locations.keys +
             snapshot.locations).uniq.sort
        end

        # The Fused value of a location; value nil when nothing counts.
        def location(name, snapshot, context: {})
            location = settings(name)
            key = [name, @setup.regime.of(snapshot.at)]
            references = location.references
            references = learned(key) if references.empty?
            learning = learning(key, references)
            parts = Parts.new(location, references, learning, snapshot,
                              @setup).all
            fused(name, snapshot.at, references&.join("+"), parts, context)
        end

        private

        # The references a location was learned against in the moment's
        # regime, else in any; nil when it was not learned.
        def learned(key)
            found = @offsets[key] ||
                    @offsets.find { |(where, _), _| where == key.first }&.last
            found && found.first.reference.split("+")
        end

        def settings(name)
            @locations.fetch(name) { Location.default(name) }
                      .resolve(@setup.quantity)
        end

        def learning(key, references)
            offsets = @offsets.fetch(key, []).to_h { [it.device, it] }
            Parts::Learning.new(
                offsets:,
                shifts: @shifts.fetch(key, []).to_h do |shift|
                    [[shift.device, shift.influence, shift.mode], shift]
                end,
                tracks: tracks(key, references, offsets)
            )
        end

        # { device => Track } of the location, those whose fingerprint is
        # the moment's: a reference's, or its Offset's.
        def tracks(key, references, offsets)
            name, regime = key
            @tracks.filter_map do |(where, device), track|
                next unless where == name && references
                print = if references.include?(device)
                            Track.reference(regime, references.join("+"))
                        else
                            offsets[device]&.then { Track.fingerprint(it) }
                        end
                [device, track] if track.fingerprint == print
            end.to_h
        end
    end
end

require_relative "fusion/outward"
