# frozen_string_literal: true

require "test_helper"
require "support/tracker_helpers"

# A reading fused again before the sensor reads again leaves its track
# as it was (README, Tracking), also when the snapshot's time has a
# fraction of a second, as Time.now has.
class TrackerRereadTest < Minitest::Test
    include TrackerHelpers

    def test_a_reading_fused_again_a_fraction_later_is_not_counted_twice
        first = moment(0)
        tracks = tracker.update({}, fusion.location("room", first))
        again = Sensorium::Snapshot.new(at: AT + Rational(7, 10),
                                        latest: first.latest)
        assert_equal tracks,
                     tracker.update(tracks, fusion.location("room", again))
    end
end
