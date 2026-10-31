# frozen_string_literal: true

require "support/fusion_helpers"

# FusionHelpers' room fused from AT on, a step every hour unless told,
# and its tracks updated from each Fused (the Fusion run without
# tracks).
module TrackerHelpers
    include FusionHelpers

    SETUP = Sensorium::Presets.room

    private

    def tracker = Sensorium::Tracker.new(SETUP, offsets:)

    # Each step's readings: the room's, as learned (ceil 20, tado 19,
    # Airzone 21), with those the block gives for the step, `every`
    # seconds apart. @states: tado's state after each step.
    def track(steps, tracks = {}, from: 0, every: 3600)
        @states = []
        steps.times do |i|
            given = block_given? ? yield(i) : {}
            fused = fusion.location("room", moment(from + i, given, every))
            tracks = tracker.update(tracks, fused)
            @states << tracks[%w[room tado]]&.state
        end
        tracks
    end

    def moment(step, given = {}, every = 3600)
        readings = { "ceil" => 20.0, "tado" => 19.0, "airzone" => 21.0 }
                   .merge(given)
        at = AT + (step * every)
        latest = readings.to_h do |device, value|
            [["room", device],
             Sensorium::Reading.new(time: at, location: "room", device:,
                                    value:)]
        end
        Sensorium::Snapshot.new(at:, latest:)
    end
end
