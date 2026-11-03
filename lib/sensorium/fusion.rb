# frozen_string_literal: true

module Sensorium
    # A location's value, fused from all its sensors: each corrected to
    # the location's reference (Parts), weighted by 1/σ², σ grown with
    # the reading's age, then, of three parts or more, Student-t
    # reweighted (Combine.robust): a sensor far from what the others
    # say (sun on it, a window open by it) keeps only a little weight,
    # and is noted "outlier".
    # A location without a reference gets its readings as they read,
    # weighted by 1/σ², σ the location's grown with each reading's age:
    # corrected false, its σ blind to how its sensors differ. The
    # offsets are those of the moment's regime.
    # The value is brought back from the transform's space with the
    # context given (a humidity at the location's fused temperature).
    class Fusion
        # value, sigma: as the quantity reads (nil when the transform
        # cannot bring them back); inside: an Estimate in the transform's
        # space; parts: [Weighted].
        Fused = Data.define(:location, :quantity, :at, :value, :sigma,
                            :inside, :reference, :corrected, :parts)
        # A Part, its share of the value (0..1), why it is left out, and
        # its value brought back as the quantity reads; untracked: the
        # Part before its Track was applied (Track#apply), the Part
        # itself when it has none, as the Tracker takes it.
        Weighted = Data.define(:part, :weight, :note, :value, :untracked) do
            def initialize(part:, untracked: part, **) = super

            # Whether a Track was applied to the Part.
            def tracked? = untracked != part
        end

        # The keywords a Fusion may be given instead of a Knowledge.
        REQUIRED = %i[offsets shifts].freeze
        OPTIONAL = %i[locations tracks dynamics collocations].freeze

        # knowledge: a Knowledge of the setup's quantity, its offsets,
        # shifts, locations (those set), tracks (the Tracker's),
        # dynamics and collocations (a sole reference's σ, where a
        # Location sets none); or, instead, those as keywords, offsets:
        # and shifts: required.
        def initialize(setup, knowledge: nil, **given)
            knowledge = Knowledge.given(knowledge, given, REQUIRED, OPTIONAL)
            @setup     = setup
            @offsets   = keyed(knowledge.offsets)
            @shifts    = keyed(knowledge.shifts)
            @locations = knowledge.locations
            @tracks    = knowledge.tracks
            @dynamics  = keyed(knowledge.dynamics).transform_values(&:first)
            @collocations = keyed(knowledge.collocations)
                            .transform_values(&:first)
        end

        # The locations it can tell: those learned, set, or read.
        def locations(snapshot)
            (@offsets.keys.map(&:first) + @locations.keys +
             snapshot.locations).uniq.sort
        end

        # The Fused value of a location; value nil when nothing counts.
        def location(name, snapshot, context: {})
            given = @locations.fetch(name) { Location.default(name) }
            key = [name, @setup.regime.of(snapshot.at)]
            references = given.references
            references = learned(key) if references.empty?
            learning = learning(key, references)
            pairs = Parts.new(settings(given, key, references), references,
                              learning, snapshot, @setup).pairs
            fused(name, snapshot.at, named(references), pairs, context)
        end

        private

        # { [location, regime] => [row] }.
        def keyed(rows) = rows.group_by { [it.location, it.regime] }

        # The references a location was learned against in the moment's
        # regime, else in any; nil when it was not learned.
        def learned(key)
            found = @offsets[key] ||
                    @offsets.find { |(where, _), _| where == key.first }&.last
            found && Sensorium.references_of(found.first.reference)
        end

        # The Location resolved (Location#resolve): its σ, when it sets
        # none, the sole reference's as learned, when it was.
        def settings(location, key, references)
            sigma = location.sigma || reference_sigma(key, references)
            location.with(sigma:).resolve(@setup.quantity)
        end

        # A sole reference's σ as the Collocation of the location and
        # regime measured it, bounded below by the quantity's floor and
        # above by the tightest σ a sensor's correction carries (its
        # Offset's spread over its scale): every one holds the
        # reference's error, so none can be narrower than it. nil with
        # several references or none, without a Collocation, or where it
        # could not measure the reference.
        def reference_sigma(key, references)
            return unless references&.one?
            name = named(references)
            found = @collocations[key]&.sigma(name) or return
            tightest = tightest(key, name) or return
            floor = @setup.quantity.floor
            found.clamp(floor, [tightest, floor].max)
        end

        # The tightest σ a correction to the reference carries.
        def tightest(key, name)
            @offsets.fetch(key, []).filter_map do |offset|
                offset.sigma / offset.scale.abs if offset.reference == name
            end.min
        end

        def learning(key, references)
            offsets = @offsets.fetch(key, []).to_h { [it.device, it] }
            Parts::Learning.new(
                offsets:,
                shifts: @shifts.fetch(key, []).to_h do |shift|
                    [[shift.device, shift.influence, shift.mode], shift]
                end,
                tracks: tracks(key, references, offsets),
                dynamics: @dynamics[key]
            )
        end

        # { device => Track } of the location, those whose fingerprint is
        # the moment's: a reference's, or its Offset's.
        def tracks(key, references, offsets)
            name, regime = key
            @tracks.filter_map do |(where, device), track|
                next unless where == name && references
                print = print(regime, references, offsets, device)
                [device, track] if track.fingerprint == print
            end.to_h
        end

        # The fingerprint a device's track must have: a reference's, or
        # its Offset's.
        def print(regime, references, offsets, device)
            if references.include?(device)
                return Track.reference(regime, named(references))
            end
            offsets[device]&.then { Track.fingerprint(it) }
        end

        def named(references)
            references && Sensorium.reference_name(references)
        end
    end
end

require_relative "fusion/outward"
