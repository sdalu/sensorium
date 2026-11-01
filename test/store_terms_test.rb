# frozen_string_literal: true

require "test_helper"
require "support/renamed_store"
require "sensorium/store/sequel"

# The terms added to an Offset come back from each store as kept.
module StoreTermsBehaviour
    AT = Time.utc(2026, 1, 10)

    def test_the_terms_come_back
        offset = rich
        @store.keep(learned(offset), from: AT, to: AT, at: AT)
        assert_equal [offset], @store.offsets("temperature")
    end

    def test_the_spreads_per_state_come_back
        offset = rich.with(states: { "heating" => [-0.3, 0.4] },
                           off_p10: -0.05, off_p90: 0.06)
        @store.keep(learned(offset), from: AT, to: AT, at: AT)
        assert_equal [offset], @store.offsets("temperature")
    end

    # A Series' spreads per level: [p10, p90, the median].
    def test_the_spreads_per_level_come_back
        offset = rich.with(states: { "solar:high" => [-0.3, 0.4, 1500.5],
                                     "solar:low" => [-0.03, 0.04, 1500.5] })
        @store.keep(learned(offset), from: AT, to: AT, at: AT)
        assert_equal [offset], @store.offsets("temperature")
    end

    private

    def learned(offset)
        Sensorium::Learned.new(quantity: "temperature", regimes: %w[winter],
                               offsets: [offset], shifts: [])
    end

    def rich
        Sensorium::Offset.new(location: "a", device: "s",
                              quantity: "temperature", regime: "winter",
                              reference: "r", constant: 0.2,
                              switches: { "heating" => 0.4 },
                              taus: { "heating" => 1800 }, gain: nil,
                              series: { "solar" => 4e-4 }, neighbour: nil,
                              coefficient: nil, rate: -0.5,
                              p10: -0.1, p90: 0.1, samples: 1000,
                              plain: 0.25, plain_p10: -0.5, plain_p90: 0.5)
    end
end

class MemoryStoreTermsTest < Minitest::Test
    include StoreTermsBehaviour

    def setup = @store = Sensorium::Store::Memory.new
end

class SequelStoreTermsTest < Minitest::Test
    include StoreTermsBehaviour

    def setup = @store = Sensorium::Store::Sequel.new(Sequel.sqlite)
end

class RenamedStoreTermsTest < Minitest::Test
    include StoreTermsBehaviour

    def setup = @store = RenamedStore.new
end
