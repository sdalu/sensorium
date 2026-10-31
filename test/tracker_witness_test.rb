# frozen_string_literal: true

require "test_helper"
require "support/tracker_helpers"

# The dynamics witness, in FusionHelpers' room of three: the reference
# ceil jumps by 1 °C and is flagged, which leaves tado and Airzone each
# with a single other. With the room's model, the previous Fused (made
# with the tracks) and the snapshot, the previous value moved by the
# model stands as a third: the two keep updating, and a bias of 0.2 on
# tado afterwards is learned. Without them, they stand still.
class TrackerWitnessTest < Minitest::Test
    include TrackerHelpers

    # A still room: no outside term, no Switch, no drift; q 0.01 per
    # hour.
    MODEL = Sensorium::Dynamics::Model.new(
        location: "room", quantity: "temperature", regime: "winter",
        a: 0.0, b: {}, c: 0.0, q: 0.01, bin: 600, steps: 1000
    )
    AIRCON = { "room" => { "aircon" => "cool" } }.freeze

    def test_with_the_witness_the_others_keep_updating
        tracks, = scenario(witness: true)
        tado = tracks.fetch(%w[room tado])
        assert_operator tado.delta, :>, 0.5 * 0.2
        assert_equal :ok, tado.state
        assert_equal :jumped, tracks.fetch(%w[room ceil]).state
    end

    def test_without_it_they_stand_still
        tracks, jumped = scenario(witness: false)
        assert_equal jumped.fetch(%w[room tado]), tracks.fetch(%w[room tado])
        assert_equal jumped.fetch(%w[room airzone]),
                     tracks.fetch(%w[room airzone])
    end

    # The model was fitted without the bins a Mode held: no witness.
    def test_a_mode_holding_makes_the_witness_stand_aside
        tracks, jumped = scenario(witness: true, modes: AIRCON)
        assert_equal jumped.fetch(%w[room tado]), tracks.fetch(%w[room tado])
    end

    private

    def witnessing
        Sensorium::Tracker.new(SETUP, offsets:, dynamics: [MODEL])
    end

    # [the tracks after 48 hourly updates of tado biased by 0.2, those
    # after the reference's jump was flagged]: ten updates of the room
    # as learned, ten of the reference reading 21, then the bias.
    def scenario(witness:, modes: {})
        healthy = steps(0, 10, [{}, nil], { witness: })
        jumped = steps(10, 10, healthy, { witness: }, "ceil" => 21.0)
        tracks, = steps(20, 48, jumped, { witness:, modes: },
                        "ceil" => 21.0, "tado" => 19.2)
        [tracks, jumped.first]
    end

    # [the tracks, the last Fused made with them] after `count` updates
    # from step `from`, from those given (state); how: witness, and the
    # modes holding; given: the readings unlike the room's as learned.
    def steps(from, count, state, how, given = {})
        updater = how[:witness] ? witnessing : tracker
        tracks, previous = state
        count.times do |i|
            snapshot = moment(from + i, given).with(modes: how[:modes] || {})
            tracks = updater.update(tracks, fusion.location("room", snapshot),
                                    **context(how[:witness], previous,
                                              snapshot))
            previous = tracked(tracks).location("room", snapshot)
        end
        [tracks, previous]
    end

    def context(witness, previous, snapshot)
        witness ? { previous:, snapshot: } : {}
    end

    def tracked(tracks)
        Sensorium::Fusion.new(SETUP, offsets:, shifts: [], tracks:)
    end
end
