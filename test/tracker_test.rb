# frozen_string_literal: true

require "test_helper"
require "support/tracker_helpers"

# Tracker: each sensor's offset followed between learnings, in
# FusionHelpers' room (ceil the reference, tado 1 °C low with σ 0.2,
# Airzone 1 °C high with σ 0.08). A step of 3 σ in tado is 0.6 °C.
class TrackerTest < Minitest::Test
    include TrackerHelpers

    # The default track_q ((σ/2)² a day, σ the quantity's 0.1) makes a
    # slow learner: a bias of 2 σ (0.2 °C) on tado takes some two days
    # of hourly updates.
    def test_a_constant_bias_is_learned_within_48_hourly_updates
        assert_learned(track(48) { { "tado" => 19.2 } })
    end

    # Ten daily updates take delta to 87 % of the same bias.
    def test_a_constant_bias_is_learned_within_ten_daily_updates
        assert_learned(track(10, every: 86_400) { { "tado" => 19.2 } })
    end

    # The CUSUM takes the innovations three hours at a time
    # (cusum_block): a step of 3 σ is flagged within twelve hours.
    def test_a_step_is_flagged_jumped_within_twelve_hours
        tracks = track(10)
        tracks = track(12, tracks, from: 10) { { "tado" => 19.6 } }
        assert_equal :jumped, tracks.fetch(%w[room tado]).state
        assert_equal :ok, tracks.fetch(%w[room airzone]).state
    end

    def test_a_slow_ramp_drifts_before_it_jumps
        track(240) { |step| { "tado" => 19.0 + (0.004 * step) } }
        drifting = @states.index(:drifting)
        refute_nil drifting
        jumped = @states.index(:jumped)
        assert jumped.nil? || drifting < jumped
    end

    # tado's Offset σ is 0.195: drifting past 0.585, back under 0.39.
    def test_drifting_clears_under_two_sigma_and_jumped_stays
        assert_equal :drifting, after(0.5, :drifting)
        assert_equal :ok, after(0.5, :ok)
        assert_equal :ok, after(0.3, :drifting)
        assert_equal :drifting, after(0.7, :ok)
        assert_equal :jumped, after(0.0, :jumped)
    end

    # A jump clears the way it came: tado 4 °C off for two readings,
    # flagged at once, then back; its delta held at the jump, the
    # return CUSUM climbs by k a block on both sides while the
    # innovations stay within k of it, past h after h / k blocks (ten:
    # thirty hours) and the open one: ok at the 33rd hourly update,
    # its CUSUM afresh.
    def test_a_jump_clears_once_the_error_is_back
        tracks = track(10)
        tracks = track(2, tracks, from: 10) { { "tado" => 23.0 } }
        assert_equal :jumped, tracks.fetch(%w[room tado]).state
        tracks = track(40, tracks, from: 12) { { "tado" => 19.0 } }
        assert_equal 33, @states.index(:ok)
        tado = tracks.fetch(%w[room tado])
        assert_equal [0.0, 0.0], [tado.cusum_up, tado.cusum_down]
    end

    # The same jump with tado staying 4 °C off: one side of the return
    # CUSUM never climbs, and the delta it is measured against does not
    # take the step in.
    def test_a_jump_stays_while_the_error_stands
        tracks = track(10)
        tracks = track(2, tracks, from: 10) { { "tado" => 23.0 } }
        tracks = track(60, tracks, from: 12) { { "tado" => 23.0 } }
        tado = tracks.fetch(%w[room tado])
        assert_equal :jumped, tado.state
        assert_in_delta 0.0, tado.delta, 1e-9
        assert_equal 0.0, tado.cusum_up
    end

    def test_a_relearned_offset_restarts_its_track
        tracks = track(10) { { "tado" => 19.1 } }
        relearned = [offset("tado", -0.9, 0.25), offset("airzone", 1.0, 0.1)]
        fused = fusion.location("room", moment(10, { "tado" => 19.1 }))
        tracker = Sensorium::Tracker.new(SETUP, offsets: relearned)
        afresh = tracker.update(tracks.except(%w[room tado]), fused)
        assert_equal afresh[%w[room tado]],
                     tracker.update(tracks, fused)[%w[room tado]]
    end

    def test_a_part_with_fewer_than_two_others_is_not_tracked
        fused = fusion.location("room", snapshot("room", { "ceil" => 20.0,
                                                           "tado" => 19.0 }))
        assert_empty tracker.update({}, fused)
    end

    def test_a_reset_track_starts_afresh
        tracks = track(10) { { "tado" => 19.6 } }
        tracks = tracker.reset(tracks, "room", "tado")
        refute tracks.key?(%w[room tado])
        assert tracks.key?(%w[room airzone])
    end

    def test_the_quantity_settings
        quantity = Sensorium::Presets::TEMPERATURE
        assert_in_delta 0.01 / 48, quantity.track_q
        assert_equal [10_800, 0.5, 5.0, 3.0, 2.0],
                     quantity.to_h.values_at(:cusum_block, :cusum_k, :cusum_h,
                                             :drift_alarm, :drift_clear)
    end

    private

    def assert_learned(tracks)
        tado = tracks.fetch(%w[room tado])
        assert_in_delta 0.2, tado.delta, 2 * Math.sqrt(tado.variance)
        assert_operator tado.delta, :>, 0.7 * 0.2
        assert_equal :ok, tado.state
    end

    # tado's state after one update from a track at delta, its readings
    # bearing that delta out.
    def after(delta, state)
        start = Sensorium::Track.fresh(offsets.first, 0.0025)
                                .with(delta:, state:, at: AT - 600)
        tracks = track(1, { %w[room tado] => start }) do
            { "tado" => 19.0 + delta }
        end
        tracks.fetch(%w[room tado]).state
    end
end
