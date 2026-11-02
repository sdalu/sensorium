# frozen_string_literal: true

require "test_helper"
require "support/tracker_helpers"

# A room of three down to two parts, in FusionHelpers' room (ceil the
# reference, tado 1 °C low with σ 0.2, Airzone 1 °C high with σ 0.08):
# once Airzone falls silent, tado is still tracked against ceil alone,
# the anchor its Offset was learned against, and ceil, left with a
# sensor alone, stands still. With two parts there is no suspect: ceil's
# CUSUM, past half of cusum_h when Airzone fell silent, would otherwise
# leave tado nothing to learn from while ceil, standing still, could
# never fall back.
class TrackerPairTest < Minitest::Test
    include TrackerHelpers

    def test_a_sensor_keeps_learning_against_the_reference_alone
        tracks = paired(suspected, 48, { "ceil" => 20.0, "tado" => 19.2 })
        assert_operator tracks.fetch(%w[room tado]).delta, :>, 0.5 * 0.2
        assert_equal :ok, tracks.fetch(%w[room tado]).state
    end

    def test_the_reference_stands_still_with_a_sensor_alone
        before = suspected
        tracks = paired(before, 48, { "ceil" => 20.0, "tado" => 19.2 })
        assert_equal before.fetch(%w[room ceil]), tracks.fetch(%w[room ceil])
    end

    # Against ceil alone, one reading 4 °C off (twenty of tado's σ) is
    # no jump by itself: one other's reading cannot tell its own spike
    # from tado's; the block under way, an hour on, can.
    def test_against_the_reference_alone_a_lone_reading_is_no_jump
        tracks = paired(suspected, 12, { "ceil" => 20.0, "tado" => 19.0 })
        tracks = paired(tracks, 1, { "ceil" => 20.0, "tado" => 23.0 }, from: 67)
        assert_equal :ok, tracks.fetch(%w[room tado]).state
        tracks = paired(tracks, 1, { "ceil" => 20.0, "tado" => 23.0 }, from: 68)
        assert_equal :jumped, tracks.fetch(%w[room tado]).state
    end

    # While the three count, ceil is the suspect: tado, left with
    # Airzone alone, stands still until ceil's CUSUM falls back.
    def test_the_suspect_stands_while_three_count
        before = suspected
        assert_operator before.fetch(%w[room ceil]).level(0.5), :>, 2.5
        tracks = track(5, before, from: 55) { { "tado" => 19.2 } }
        assert_equal before.fetch(%w[room tado]), tracks.fetch(%w[room tado])
    end

    private

    # The tracks after 48 healthy hourly updates and two blocks of ceil
    # reading 0.3 high: ceil's CUSUM past half of cusum_h, not jumped.
    def suspected
        tracks = track(48)
        tracks = track(7, tracks, from: 48) { { "ceil" => 20.3 } }
        assert_equal :ok, tracks.fetch(%w[room ceil]).state
        tracks
    end

    # The tracks after `count` hourly updates of the room reduced to
    # the readings given, from step `from` on.
    def paired(tracks, count, readings, from: 55)
        count.times.reduce(tracks) do |done, i|
            at = AT + ((from + i) * 3600)
            latest = readings.to_h do |device, value|
                [["room", device],
                 Sensorium::Reading.new(time: at, location: "room", device:,
                                        value:)]
            end
            snapshot = Sensorium::Snapshot.new(at:, latest:)
            tracker.update(done, fusion.location("room", snapshot))
        end
    end
end
