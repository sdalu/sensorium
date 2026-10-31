# frozen_string_literal: true

require "test_helper"
require "sensorium/store/sequel"

# A Filter's states, kept between runs: one per location and quantity,
# replaced by a keep.
module StoreFiltersBehaviour
    AT = Time.utc(2026, 1, 10, 12)

    def test_states_come_back
        @store.keep_filters("temperature", [state("room", 20.5)])
        found = @store.filters("temperature").fetch("room")
        assert_in_delta 20.5, found.value
        assert_in_delta 0.0025, found.variance
        assert_equal AT, found.at
        assert_empty @store.filters("humidity")
    end

    def test_a_keep_replaces_the_states_of_its_quantity
        @store.keep_filters("temperature", [state("a", 20.0), state("b", 21.0)])
        @store.keep_filters("temperature", [state("a", 22.0)])
        assert_equal %w[a], @store.filters("temperature").keys
        assert_in_delta 22.0, @store.filters("temperature")["a"].value
    end

    private

    def state(location, value)
        Sensorium::Filter::State.new(location:, quantity: "temperature",
                                     at: AT, value:, variance: 0.0025)
    end
end

class MemoryStoreFiltersTest < Minitest::Test
    include StoreFiltersBehaviour

    def setup = @store = Sensorium::Store::Memory.new
end

class SequelStoreFiltersTest < Minitest::Test
    include StoreFiltersBehaviour

    def setup = @store = Sensorium::Store::Sequel.new(Sequel.sqlite)
end
