# frozen_string_literal: true

require "test_helper"
require "support/tracker_helpers"

# Fusion with tracks: a tracked part's corrected value has its delta
# taken out and its σ² the track's variance added; a jumped one does
# not count.
class TrackedFusionTest < Minitest::Test
    include TrackerHelpers

    # tado's σ (p10..p90 0.5) with a track's variance of 0.03².
    TADO_SIGMA = Math.hypot(0.5 / Sensorium::P10_P90, 0.03)

    # Until tado's own delta has caught up with its step, Airzone's
    # takes in a little of it (-0.03 °C after twelve updates).
    def test_a_step_jumped_then_does_not_count
        tracks = track(10)
        tracks = track(12, tracks, from: 10) { { "tado" => 19.6 } }
        fused = tracked(tracks).location("room",
                                         moment(22, { "tado" => 19.6 }))
        assert_equal "jumped", note(fused, "tado")
        assert_nil part(fused, "tado").part.value
        assert_in_delta 0.0, weight(fused, "tado")
        assert_in_delta 20.0, fused.value, 0.03
    end

    # ceil, the sole reference (σ 0.1), steps by 5 σ: its track jumps
    # within ten hourly updates, tado's and Airzone's do not, and from
    # the flag on the fused value, without ceil, stays within 2 σ of
    # the truth (20 °C).
    def test_a_reference_that_jumps_is_flagged_and_left_out
        tracks = track(10)
        flagged = 10.times.map do |i|
            tracks = track(1, tracks, from: 10 + i) { { "ceil" => 20.5 } }
            tracks.fetch(%w[room ceil]).state == :jumped &&
                truth_kept?(tracks, 10 + i)
        end
        assert flagged.last
        assert_equal [:ok], tracks.values_at(%w[room tado], %w[room airzone])
                                  .map(&:state).uniq
    end

    def test_a_drifting_part_counts_with_its_delta_taken_out
        tado = part(tracked(tado(0.7, :drifting))
                    .location("room", moment(0, { "tado" => 19.7 })), "tado")
        assert_equal "drifting", tado.note
        assert_in_delta 20.0, tado.part.value
        assert_in_delta TADO_SIGMA, tado.part.sigma
        assert_operator tado.weight, :>, 0.05
    end

    # ceil, the sole reference, its Location's σ 0.05, with the track
    # the Tracker keeps for it (delta 0, variance (σ/2)² of the
    # quantity's σ, never moved): a reference is weighted by the
    # location's σ, and its pinned track adds nothing to it.
    def test_a_references_pinned_track_leaves_its_sigma
        locations = { "room" => Sensorium::Location.new(name: "room",
                                                        sigma: 0.05) }
        fusion = Sensorium::Fusion.new(SETUP, offsets:, shifts: [], locations:,
                                              tracks: pinned("ceil"))
        fused = fusion.location("room", moment(0))
        assert_in_delta 0.05, part(fused, "ceil").part.sigma, 1e-9
    end

    def test_a_part_that_does_not_count_keeps_its_note
        readings = { "ceil" => 20.0, "tado" => [19.7, 7200] }
        fused = tracked(tado(0.7, :jumped))
                .location("room", snapshot("room", readings))
        assert_equal "stale", note(fused, "tado")
    end

    def test_a_track_of_another_offset_is_left_out
        fused = tracked(tado(0.7, :jumped, constant: -1.5))
                .location("room", moment(0))
        assert_nil note(fused, "tado")
        assert_in_delta 20.0, part(fused, "tado").part.value
    end

    private

    # Whether, with the tracks, ceil does not count and the fused value
    # is within 2 σ of 20 °C.
    def truth_kept?(tracks, step)
        fused = tracked(tracks).location("room",
                                         moment(step, { "ceil" => 20.5 }))
        assert_equal "jumped", note(fused, "ceil")
        assert_in_delta 20.0, fused.value, 2 * fused.sigma
        true
    end

    def tracked(tracks)
        Sensorium::Fusion.new(SETUP, offsets:, shifts: [], tracks:)
    end

    # A reference's track as the Tracker starts it (Tracker::Basis).
    def pinned(device)
        { ["room", device] => Sensorium::Track.start(
            location: "room", device:, quantity: "temperature",
            regime: "winter", reference: device,
            variance: (SETUP.quantity.sigma / 2)**2
        ) }
    end

    def tado(delta, state, constant: -1.0)
        { %w[room tado] => Sensorium::Track.fresh(offsets.first, 0.0009)
                                           .with(delta:, state:, constant:,
                                                 at: AT) }
    end
end
