# frozen_string_literal: true

require "test_helper"
require "support/renamed_store"
require "sensorium/store/sequel"
require "support/winter"

# A sensor gone for good: a learning whose source no longer lists it
# drops its offsets and shifts in every regime; Store#forget drops a
# sensor's offsets, shifts and track on demand.
module StoreForgetBehaviour
    WINTER = Winter.learned
    GONE   = %w[room-a airzone].freeze

    def test_a_sensor_no_longer_listed_is_dropped
        keep(WINTER)
        keep(WINTER.with(regimes: %w[summer], offsets: [], shifts: [],
                         sensors: listed - [GONE]))
        refute(offsets.any? { key(it) == GONE })
        refute(@store.shifts("temperature").any? { key(it) == GONE })
    end

    # Listed but short of samples this time: kept, as before.
    def test_a_sensor_still_listed_is_kept
        keep(WINTER)
        keep(WINTER.with(regimes: %w[summer], offsets: [], shifts: [],
                         sensors: listed))
        assert_equal WINTER.offsets.size, offsets.size
    end

    # A learning that does not say what was listed drops nothing.
    def test_without_the_list_nothing_is_dropped
        keep(WINTER)
        keep(WINTER.with(regimes: %w[summer], offsets: [], shifts: []))
        assert_equal WINTER.offsets.size, offsets.size
    end

    def test_forget_drops_a_sensors_offsets_and_shifts
        keep(WINTER)
        @store.forget("temperature", *GONE)
        refute(offsets.any? { key(it) == GONE })
        refute(@store.shifts("temperature").any? { key(it) == GONE })
        assert_equal WINTER.offsets.size - 1, offsets.size
    end

    def test_forget_drops_a_sensors_track
        @store.keep_tracks("temperature", { GONE => track })
        @store.forget("temperature", *GONE)
        assert_empty @store.tracks("temperature")
    end

    private

    def offsets = @store.offsets("temperature")
    def key(row) = [row.location, row.device]

    def listed = WINTER.offsets.to_set { key(it) }

    def keep(learned)
        @store.keep(learned, from: FakeHouse::START, to: FakeHouse::START,
                             at: FakeHouse::START)
    end

    def track
        Sensorium::Track.new(location: "room-a", device: "airzone",
                             quantity: "temperature", regime: "winter",
                             reference: "ceil-a", constant: 1.1, plain: 1.1,
                             delta: 0.0, variance: 0.01, cusum_up: 0.0,
                             cusum_down: 0.0, at: FakeHouse::START,
                             state: :ok)
    end
end

class MemoryStoreForgetTest < Minitest::Test
    include StoreForgetBehaviour

    def setup = @store = Sensorium::Store::Memory.new
end

class SequelStoreForgetTest < Minitest::Test
    include StoreForgetBehaviour

    def setup = @store = Sensorium::Store::Sequel.new(Sequel.sqlite)
end

class RenamedStoreForgetTest < Minitest::Test
    include StoreForgetBehaviour

    def setup = @store = RenamedStore.new
end
