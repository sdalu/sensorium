# frozen_string_literal: true

require "test_helper"
require "support/tracker_helpers"

# The Tracker given transient profiles: while the Detector finds an
# event in a location at the moment, its parts are left as they were.
class TrackerTransientTest < Minitest::Test
    include TrackerHelpers

    def test_a_location_is_skipped_during_an_event
        tracks = track(5) { { "tado" => 19.2 } }
        snapshot = moment_with(tado: [19.2, 17.0])
        fused = fusion.location("room", snapshot)
        assert_equal tracks, watching.update(tracks, fused, snapshot:)
        refute_equal tracks, tracker.update(tracks, fused, snapshot:)
    end

    def test_a_calm_moment_is_tracked_as_without_profiles
        tracks = track(5) { { "tado" => 19.2 } }
        snapshot = moment_with(tado: [19.2, 19.2])
        fused = fusion.location("room", snapshot)
        assert_equal tracker.update(tracks, fused),
                     watching.update(tracks, fused, snapshot:)
    end

    # Without the snapshot, nothing to detect from.
    def test_without_a_snapshot_it_tracks_as_before
        tracks = track(5) { { "tado" => 19.2 } }
        fused = fusion.location("room", moment_with(tado: [19.2, 17.0]))
        assert_equal tracker.update(tracks, fused),
                     watching.update(tracks, fused)
    end

    private

    def watching
        Sensorium::Tracker.new(SETUP, offsets:, transients: [profile])
    end

    def profile
        threshold = Sensorium::Transient::Threshold.new(fall: -0.5,
                                                        rise: 0.5)
        Sensorium::Transient::Profile.new(
            location: "room", device: "tado", quantity: "temperature",
            regime: "winter", own: { 600 => threshold }, relative: {}
        )
    end

    # The moment after the five steps, tado reading `before` ten minutes
    # earlier and `now` at the moment.
    def moment_with(tado:)
        before, now = tado
        snapshot = moment(5, { "tado" => now })
        latest = snapshot.latest[%w[room tado]]
        earlier = latest.with(time: snapshot.at - 600, value: before)
        snapshot.with(history: { %w[room tado] => [earlier, latest] })
    end
end
