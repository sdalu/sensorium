# frozen_string_literal: true

require "test_helper"
require "support/recorded_room"

# A real room, recorded (RecordedRoom): learned on its first twenty
# days, fused on the last ten. Bounds around what it gave when
# recorded: two offsets beside the ceiling's, every part left out
# hourly with var(z) 0.43..0.83 and an RMS gap of 0.28 °C, no part
# flagged by the Tracker hourly, three transient profiles. Skipped
# without the recording.
class RecordedRoomTest < Minitest::Test
    SETUP = Sensorium::Presets.room
    DAYS  = 20

    def self.memo = @memo ||= {}

    def setup
        @room = RecordedRoom.load or skip "no #{RecordedRoom::PATH}"
        @split = @room.from + (DAYS * 86_400)
    end

    def test_every_sensor_beside_the_reference_is_learned
        assert_equal %w[valve-1 wall-1], learned.offsets.map(&:device).sort
    end

    def test_no_part_is_overconfident
        scores.each do |device, (zs, _)|
            assert_operator var(zs), :<=, 1.25, device
            assert_operator var(zs), :>=, 0.3, device
        end
    end

    def test_a_part_left_out_is_near_what_the_others_fuse_to
        ds = scores.values.flat_map(&:last)
        assert_operator Math.sqrt(ds.sum { it**2 } / ds.size), :<, 0.35
    end

    # Each sensor's error persists for hours (an afternoon's swing):
    # tracked hourly over the last ten days, no part is flagged, where
    # a CUSUM taking each hour alone flagged wall-1 within eleven hours.
    def test_no_part_jumps_over_the_last_ten_days
        tracks = instants.reduce({}) do |kept, at|
            snapshot = Sensorium::Snapshot.from(@room, SETUP, at:)
            fused = fusion.location(RecordedRoom::ROOM, snapshot)
            tracker.update(kept, fused, snapshot:)
        end
        assert_equal 3, tracks.size
        assert_equal [:ok], tracks.values.map(&:state).uniq
    end

    def test_each_sensor_has_a_transient_profile
        profiles = Sensorium::Transient.learn(@room, SETUP, from: @room.from,
                                                            to: @split)
        assert_equal 3, profiles.size
    end

    private

    def learned
        self.class.memo[:learned] ||=
            Sensorium::Learner.new(@room, SETUP, from: @room.from,
                                                 to: @split).learn
    end

    # { device => [[z], [d]] } of every part left out, hourly.
    def scores = self.class.memo[:scores] ||= scored

    def fusion
        Sensorium::Fusion.new(SETUP, offsets: learned.offsets,
                                     shifts: learned.shifts)
    end

    def tracker = Sensorium::Tracker.new(SETUP, offsets: learned.offsets)

    def scored
        fusion = self.fusion
        instants.each_with_object({}) do |at, scores|
            parts(fusion, at).then { score(it, scores) }
        end
    end

    def instants
        (@split.to_i...@room.to.to_i).step(3600).map { Time.at(it).utc }
    end

    def parts(fusion, at)
        snapshot = Sensorium::Snapshot.from(@room, SETUP, at:)
        fusion.location(RecordedRoom::ROOM, snapshot).parts.map(&:part)
              .select(&:value)
    end

    def score(parts, scores)
        return if parts.size < 3
        parts.each do |part|
            z, d = left_out(part, parts - [part])
            zs, ds = scores[part.device] ||= [[], []]
            zs << z
            ds << d
        end
    end

    # [z, d] of a part against what the others fuse to.
    def left_out(part, others)
        value, sigma = Sensorium::Combine.robust(others,
                                                 SETUP.quantity.robust_nu)
        d = part.value - value
        [d / Math.sqrt((part.sigma**2) + (sigma**2)), d]
    end

    def var(zs)
        mean = zs.sum / zs.size
        zs.sum { (it - mean)**2 } / (zs.size - 1)
    end
end
