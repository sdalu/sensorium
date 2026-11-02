# frozen_string_literal: true

require "test_helper"
require "support/tracker_helpers"

# The return CUSUM of a jumped track (Tracker::Step#returning): "both
# sides above h, at least h / k = 10 blocks (30 h) of the error back,
# and it is ok again" (DESIGN.md, A jump clears the way it came), the
# error "within k of the delta held" (step.rb).
class TrackerReturnTest < Minitest::Test
    include TrackerHelpers

    # tado 4 °C high, flagged at once and held away for twelve hours,
    # then 1 °C low (five of its σ the other side of the delta held):
    # never back within k, so it stays jumped. On v0.4.0 the down side,
    # which climbed by k + z every block while the error was away up,
    # is already far past h, and the up side passes h at the first
    # block closed: ok again at the fourth hourly update, for four
    # hours, a 5 σ error counted, until its fresh CUSUM flags it again.
    def test_an_error_on_the_other_side_is_not_back
        tracks = away
        track(12, tracks, from: 24) { { "tado" => 18.0 } }
        refute_includes @states, :ok
    end

    # The same, 0.2 °C low (about one of tado's σ, z about -0.9 against
    # k = 0.5): on v0.4.0 ok at the 13th hourly update, sooner than an
    # error fully back (33rd, TrackerTest), fewer than h / k = 10 blocks,
    # and it stays ok, the error never within k.
    def test_no_clear_before_ten_blocks
        tracks = away
        track(30, tracks, from: 24) { { "tado" => 18.8 } }
        refute_includes @states, :ok
    end

    private

    def away
        tracks = track(10)
        tracks = track(14, tracks, from: 10) { { "tado" => 23.0 } }
        assert_equal :jumped, tracks.fetch(%w[room tado]).state
        tracks
    end
end
