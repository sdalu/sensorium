# frozen_string_literal: true

require "test_helper"
require "support/tracker_helpers"

# A reference's innovations are judged with the room's width: the
# tightest Offset σ of the location, where the quantity's σ (the
# instrument's own error) is narrower. In a room whose two sensors
# disagree with ceil by σ 0.31 each (p10..p90 ±0.4), ceil reading
# 0.3 high is within what the room usually sees of it: three days of
# it flag no part, and the others' deltas take the level in; judged
# with the quantity's 0.1, ceil was flagged at the 31st hour.
class TrackerReferenceTest < Minitest::Test
    include TrackerHelpers

    def offsets = [offset("tado", -1.0, 0.4), offset("airzone", 1.0, 0.4)]

    def test_a_reference_is_judged_with_the_rooms_width
        tracks = track(48)
        tracks = track(72, tracks, from: 48) { { "ceil" => 20.3 } }
        assert_equal [:ok], tracks.values.map(&:state).uniq
        assert_in_delta(-0.24, tracks.fetch(%w[room tado]).delta, 0.02)
    end

    # The quantity's σ stays the floor: in FusionHelpers' room (Airzone
    # σ 0.08) ceil is judged with 0.1, and 0.5 high is flagged within a
    # day, as before.
    def test_the_quantitys_sigma_is_the_floor
        helpers = Narrow.new
        tracks = helpers.track(48)
        tracks = helpers.track(24, tracks, from: 48) { { "ceil" => 20.5 } }
        assert_equal :jumped, tracks.fetch(%w[room ceil]).state
    end

    # FusionHelpers' room as it is.
    class Narrow
        include TrackerHelpers

        public :track
    end
end
