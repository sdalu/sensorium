# frozen_string_literal: true

require "test_helper"
require "support/tracker_helpers"

# The Tracker's widths in the correction's space, where delta and the
# innovations are: an Offset's σ is its gap's spread, a correction's is
# that over the scale (Offset#correct). tado here has a neighbour term,
# k = 0.6 against hall/n, so its gap's σ 0.195 (p10..p90 ±0.25) is a
# correction's 0.122: drifting past 3 × 0.122 = 0.37 °C of delta, where
# the gap's σ put the alarm at 0.59, 4.8 of the correction's σ.
class TrackerSpacesTest < Minitest::Test
    include TrackerHelpers

    K = 0.6

    def offsets
        [offset("tado", -1.0, 0.25).with(neighbour: "hall/n", coefficient: K),
         offset("airzone", 1.0, 0.1)]
    end

    def test_drifting_is_judged_in_the_corrections_sigma
        assert_equal :drifting, after(0.45, :ok)
        assert_equal :ok, after(0.2, :drifting)
        assert_equal :drifting, after(0.3, :drifting)
    end

    # The reference's width is the tightest Offset σ, a correction's:
    # with both sensors at k = 0.6 and p10..p90 ±0.4 (gap σ 0.31, a
    # correction's 0.195), ceil 0.4 high is flagged within a day (at the
    # 16th hour) and the sensors are not; judged with the gap's σ, ceil
    # was not flagged within three days, and both sensors were.
    def test_the_references_width_is_a_corrections
        wide = [offset("tado", -1.0, 0.4), offset("airzone", 1.0, 0.4)]
        @offsets = wide.map { it.with(neighbour: "hall/n", coefficient: K) }
        tracks = track(48)
        tracks = track(24, tracks, from: 48) { { "ceil" => 20.4 } }
        assert_equal %i[jumped ok ok],
                     tracks.values_at(%w[room ceil], %w[room tado],
                                      %w[room airzone]).map(&:state)
    end

    private

    # tado's state after one update from a track at delta, its readings
    # bearing that delta out (a corrected value delta above the truth
    # is a reading (1 + k) × delta above the learned one).
    def after(delta, state)
        start = Sensorium::Track.fresh(offsets.first, 0.0025)
                                .with(delta:, state:, at: AT - 600)
        tracks = track(1, { %w[room tado] => start }) do
            { "tado" => 19.0 + ((1 + K) * delta) }
        end
        tracks.fetch(%w[room tado]).state
    end

    def tracker = Sensorium::Tracker.new(SETUP, offsets: @offsets || offsets)

    def fusion
        Sensorium::Fusion.new(SETUP, offsets: @offsets || offsets, shifts: [])
    end

    # The room's readings with hall/n at 20 °C, ceil's level: r - n = 0,
    # so tado's correction is (reading + 1 + k × 20) / (1 + k).
    def moment(step, given = {}, every = 3600)
        snapshot = super
        at = snapshot.at
        hall = Sensorium::Reading.new(time: at, location: "hall", device: "n",
                                      value: 20.0)
        snapshot.with(latest: snapshot.latest.merge(%w[hall n] => hall))
    end
end
