# frozen_string_literal: true

require "test_helper"

# A Mode's value holds over its hold after each event, in learning as in
# the Fusion (DESIGN.md, Learning). With a bin that does not divide the
# hold (480 s against 1800 s), an event late in its bin still holds at a
# moment the Snapshot finds it holding, and so does the Timeline at the
# bin of that moment: the hold counts from the event, not its bin.
class HoldFromEventTest < Minitest::Test
    START = Time.utc(2026, 1, 5)
    EVENT = START + 400                         # late in the bin START

    class Source
        def initialize(events) = @events = events
        def sensors(_quantity) = []
        def readings(_quantity, _from, _to, _devices = nil) = []

        def events(name, from, to)
            return [] unless name == "aircon"
            @events.select { (from..to).cover?(it.first) }
        end
    end

    def test_a_mode_holds_in_learning_where_the_fusion_holds_it
        setup = setup_with(Sensorium::Influence::Mode, 1800)
        source = Source.new([[EVENT, "room", "cooling"]])
        at = EVENT + 1700                       # within the hold
        snapshot = Sensorium::Snapshot.from(source, setup, at:)
        assert_equal [%w[aircon cooling]], snapshot.holding("room")

        timeline = timeline(setup, source)
        bin = setup.series.bin(at)
        assert timeline.near?("room", bin),
               "the bin of a moment the Fusion holds the Mode is calm"
        assert_equal [%w[aircon cooling]], timeline.modes("room", bin)
    end

    # The same for a Switch: on in the Fusion, on in its learning.
    def test_a_switch_is_on_in_learning_where_the_fusion_has_it_on
        setup = setup_with(Sensorium::Influence::Switch, 3600)
        source = Source.new([[EVENT, "room", true]])
        at = EVENT + 3500
        snapshot = Sensorium::Snapshot.from(source, setup, at:)
        assert_equal %w[aircon], snapshot.on("room")

        on = timeline(setup, source).switches("room").fetch("aircon")
        assert_includes on, setup.series.bin(at)
    end

    private

    def setup_with(kind, hold)
        Sensorium::Setup.new(
            quantity: Sensorium::Presets::TEMPERATURE, bin: 480,
            influences: [kind.new(name: "aircon", hold:)]
        )
    end

    def timeline(setup, source)
        Sensorium::Timeline.new(setup, source, START - 3600, START + 7200)
    end
end
