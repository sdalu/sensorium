# frozen_string_literal: true

require "test_helper"
require "support/fusion_helpers"

# A regime is asked of local times wherever the moment comes from: a
# History asks of Time.at(bin), and the Fusion, the Detector and the
# Tracker of the snapshot's at, which a Store reads back in UTC. A
# regime of its own (any object answering of) must not see both.
class RegimeLocalTest < Minitest::Test
    include FusionHelpers

    # Answers "winter", noting whether each time it was asked of was
    # UTC.
    class Recording
        attr_reader :names, :asked

        def initialize
            @names = ["winter"].freeze
            @asked = []
        end

        def of(time)
            @asked << time.utc?
            "winter"
        end

        def covered(_from, _to) = @names
    end

    def test_the_fusion_detector_and_tracker_ask_of_local_times
        regime = Recording.new
        setup = Sensorium::Presets.room.with(regime:)
        snapshot = snapshot("room", { "ceil" => 20.0, "tado" => 19.0,
                                      "airzone" => 21.0 })
        asked(setup, snapshot)
        assert_operator regime.asked.size, :>=, 3
        assert_equal [false], regime.asked.uniq
    end

    private

    def asked(setup, snapshot)
        fused = fusion(setup:).location("room", snapshot)
        Sensorium::Transient::Detector.new(setup, profiles: [])
                                      .events(snapshot)
        Sensorium::Tracker.new(setup, offsets:).update({}, fused)
    end
end
