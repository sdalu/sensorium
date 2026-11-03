# frozen_string_literal: true

require "test_helper"
require "sensorium/store/sequel"
require "support/winter"

# The times a caller gives Store::Sequel are kept as given: converted
# to UTC in a copy, never in place, so a frozen one is taken too, as
# Store::Memory takes it.
class StoreGivenTimeTest < Minitest::Test
    def test_a_frozen_local_time_is_kept
        at = Time.new(2026, 1, 15, 12, 0, 0, "+01:00").freeze
        store = Sensorium::Store::Sequel.new(Sequel.sqlite)
        store.keep(Winter.learned, from: at - 86_400, to: at, at:)
        assert_equal at, store.learned("temperature")["winter"].last
    end

    def test_the_callers_time_is_left_as_given
        at = Time.new(2026, 1, 15, 12, 0, 0, "+01:00")
        store = Sensorium::Store::Sequel.new(Sequel.sqlite)
        store.keep(Winter.learned, from: at - 86_400, to: at, at:)
        assert_equal 3600, at.utc_offset
    end

    def test_a_frozen_local_time_is_tracked
        at = Time.new(2026, 1, 15, 12, 0, 0, "+01:00").freeze
        track = Sensorium::Track.new(
            location: "room", device: "tado", quantity: "temperature",
            regime: "winter", reference: "ceil", constant: -1.0, plain: -1.0,
            delta: 0.0, variance: 0.01, cusum_up: 0.0, cusum_down: 0.0,
            at:, block_at: at, state: :ok
        )
        store = Sensorium::Store::Sequel.new(Sequel.sqlite)
        store.keep_tracks("temperature", { %w[room tado] => track })
        assert_equal at, store.tracks("temperature")[%w[room tado]].at
    end
end
