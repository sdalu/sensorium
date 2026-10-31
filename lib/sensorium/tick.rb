# frozen_string_literal: true

module Sensorium
    # One cycle of the fusion, every ten minutes say, for one quantity:
    # each location fused once, with the tracks (Fusion), the tracks
    # updated from those Fused (Tracker), and the transients of the
    # moment (Transient::Detector), all from one Knowledge. A Tick holds
    # nothing between calls: the tracks it gives back, kept, and the
    # Fused, given back as previous, are the next call's.
    class Tick
        # fused: { location => Fusion::Fused }, made with the tracks;
        # tracks: { [location, device] => Track }, those given, updated;
        # events: [Transient::Event].
        Result = Data.define(:fused, :tracks, :events)

        # knowledge: a Knowledge of the setup's quantity.
        def initialize(setup, knowledge)
            @tracks   = knowledge.tracks
            @fusion   = Fusion.new(setup, knowledge:)
            @tracker  = Tracker.new(setup, knowledge:)
            @detector = Transient::Detector.new(setup, knowledge:)
        end

        # The Result of the snapshot; previous: { location => Fused }, the
        # last call's, for the Tracker's witness.
        def call(snapshot, previous: {})
            fused = @fusion.locations(snapshot).to_h do |name|
                [name, @fusion.location(name, snapshot)]
            end
            Result.new(fused:, tracks: tracked(fused, snapshot, previous),
                       events: @detector.events(snapshot))
        end

        private

        def tracked(fused, snapshot, previous)
            fused.reduce(@tracks) do |tracks, (name, one)|
                @tracker.update(tracks, one, previous: previous[name],
                                             snapshot:)
            end
        end
    end
end
