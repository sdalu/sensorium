# frozen_string_literal: true

require "test_helper"
require "support/tracker_helpers"

# A Tick may run more often than the sensors read: a track takes each
# reading once, so the tracks do not depend on how often the room is
# fused.
class TrackerCadenceTest < Minitest::Test
    include TrackerHelpers

    READ = 300
    SPAN = 12 * 3600

    def test_the_same_fused_twice_moves_nothing
        fused = fusion.location("room", moment(0, { "tado" => 19.3 }))
        once = tracker.update({}, fused)
        assert_equal once, tracker.update(once, fused)
    end

    # Readings every five minutes, tado stepping 0.6 °C (3 σ) after the
    # first hour: fused every minute or every five, the same tracks.
    def test_fusing_every_minute_is_fusing_at_each_reading
        assert_equal fused_every(60), fused_every(READ)
    end

    # The CUSUM takes the innovations by blocks of time, not by
    # updates: the step is flagged at the same reading at any cadence,
    # within six hours of it.
    def test_a_step_is_flagged_at_the_same_reading_at_any_cadence
        firsts = [60, READ].map do |every|
            states = states_every(every)
            states.find { |_, state| state == :jumped }&.first
        end
        refute_nil firsts.first
        assert_equal firsts.first, firsts.last
        assert_operator firsts.first, :<=, 3600 + (6 * 3600)
    end

    private

    # tado's [reading time, state] after each fusion, twelve hours
    # long.
    def states_every(every)
        tracks = {}
        (0...SPAN).step(every).map do |second|
            tracks = tracker.update(tracks, at(second))
            [(second / READ) * READ, tracks[%w[room tado]].state]
        end
    end

    def fused_every(every)
        (0...7200).step(every).reduce({}) do |tracks, second|
            tracker.update(tracks, at(second))
        end
    end

    # The room fused at AT + second, each sensor's latest reading the
    # one taken at the last five-minute mark.
    def at(second)
        read = (second / READ) * READ
        tado = read >= 3600 ? 19.6 : 19.0
        readings = { "ceil" => 20.0, "tado" => tado, "airzone" => 21.0 }
        latest = readings.to_h do |device, value|
            [["room", device],
             Sensorium::Reading.new(time: AT + read, location: "room",
                                    device:, value:)]
        end
        snapshot = Sensorium::Snapshot.new(at: AT + second, latest:)
        fusion.location("room", snapshot)
    end
end
