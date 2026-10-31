# frozen_string_literal: true

require "test_helper"
require "support/fusion_helpers"

# A Tick of humidity: each location's value is brought back from
# absolute humidity at that location's temperature, given as context.
class TickContextTest < Minitest::Test
    include FusionHelpers

    SETUP = Sensorium::Presets.room(Sensorium::Presets::HUMIDITY)
    ROOM  = { temperature: 20.0 }.freeze

    def test_a_location_s_context_brings_its_value_back
        result = tick.call(snapshot("room", readings),
                           context: { "room" => ROOM })
        assert_in_delta 50.0, result.fused["room"].value, 0.01
    end

    # A callable context, asked by location.
    def test_a_context_may_be_asked_for
        asked = []
        context = lambda do |location|
            asked << location
            ROOM
        end
        result = tick.call(snapshot("room", readings), context:)
        assert_equal %w[room], asked
        assert_in_delta 50.0, result.fused["room"].value, 0.01
    end

    def test_without_context_no_value
        result = tick.call(snapshot("room", readings))
        assert_nil result.fused["room"].value
    end

    private

    def tick
        knowledge = Sensorium::Knowledge.new(
            offsets: [offset("tado", 0.0, 0.1, quantity: "humidity")]
        )
        Sensorium::Tick.new(SETUP, knowledge)
    end

    def readings
        { "ceil" => [50.0, 0, ROOM], "tado" => [50.0, 0, ROOM] }
    end
end
