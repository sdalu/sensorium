# frozen_string_literal: true

require "test_helper"
require "support/tracker_helpers"

# The Tracker takes a sensor's innovations three hours at a time
# (cusum_block), in FusionHelpers' room (ceil the reference, tado 1 °C
# low with σ 0.2, Airzone 1 °C high with σ 0.08): its CUSUM runs on each
# block's mean, its delta moves once a block closes.
class TrackerBlocksTest < Minitest::Test
    include TrackerHelpers

    # tado swinging by one and a half of its σ over the day, hourly for
    # ten days: taken hour by hour, the swing adds up past cusum_h within
    # its first day (at 19 h); taken by blocks, it does not.
    def test_a_daily_swing_is_not_a_jump
        track(240) do |step|
            { "tado" => 19.0 + (0.3 * Math.sin(2 * Math::PI * step / 24)) }
        end
        refute_includes @states, :jumped
    end

    def test_the_delta_moves_only_when_a_block_closes
        tracks = track(3) { { "tado" => 19.2 } }
        assert_in_delta 0.0, tracks.fetch(%w[room tado]).delta
        tracks = track(1, tracks, from: 3) { { "tado" => 19.2 } }
        assert_operator tracks.fetch(%w[room tado]).delta, :>, 0.0
    end

    # 4 °C off, twenty of tado's σ: no block need close.
    def test_a_step_far_beyond_the_noise_is_flagged_at_once
        tracks = track(48)
        tracks = track(1, tracks, from: 48) { { "tado" => 23.0 } }
        assert_equal :jumped, tracks.fetch(%w[room tado]).state
    end

    # ceil, the reference, steps by 5 of its σ: while its CUSUM climbs it
    # is the suspect, left out of tado's and Airzone's truth, so neither
    # takes in the step before ceil is flagged.
    def test_a_reference_step_leaks_into_no_other_delta
        tracks = track(48)
        12.times do |i|
            tracks = track(1, tracks, from: 48 + i) { { "ceil" => 20.5 } }
            break if tracks.fetch(%w[room ceil]).state == :jumped
        end
        assert_equal :jumped, tracks.fetch(%w[room ceil]).state
        %w[tado airzone].each do |device|
            assert_in_delta 0.0, tracks.fetch(["room", device]).delta, 0.01
        end
    end
end
