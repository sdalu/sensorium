# frozen_string_literal: true

module Sensorium
    # One cycle of the fusion, every ten minutes say, for one quantity:
    # each location fused once, with the tracks (Fusion), the tracks
    # updated from those Fused (Tracker), and the transients of the
    # moment (Transient::Detector), all from one Knowledge. A Tick holds
    # nothing between calls: the tracks it gives back, kept, are the
    # next call's.
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

        # The Result of the snapshot; context: { location => context },
        # or anything answering call(location) with one, for the value
        # brought back from the transform's space (a humidity at the
        # location's temperature).
        def call(snapshot, context: {})
            fused = @fusion.locations(snapshot).to_h do |name|
                [name, @fusion.location(name, snapshot,
                                        context: context_of(context, name))]
            end
            Result.new(fused:, tracks: tracked(fused, snapshot),
                       events: @detector.events(snapshot))
        end

        private

        def context_of(context, name)
            return context.call(name) || {} if context.respond_to?(:call)
            context.fetch(name, {})
        end

        def tracked(fused, snapshot)
            fused.values.reduce(@tracks) do |tracks, one|
                @tracker.update(tracks, one, snapshot:)
            end
        end
    end
end
