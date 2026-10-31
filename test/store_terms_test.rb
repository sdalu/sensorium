# frozen_string_literal: true

require "test_helper"
require "sensorium/store/sequel"

# The terms added to an Offset come back from each store as kept.
module StoreTermsBehaviour
    AT = Time.utc(2026, 1, 10)

    def test_the_terms_come_back
        offset = rich
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
                              switches: { "heating" => 0.4 }, gain: nil,
                              neighbour: nil, coefficient: nil, rate: -0.5,
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
