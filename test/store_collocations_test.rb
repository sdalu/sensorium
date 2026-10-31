# frozen_string_literal: true

require "test_helper"
require "sensorium/store/sequel"

# A location's Collocations come back from each store as kept; a later
# keep replaces those of the same location and regime only.
module StoreCollocationsBehaviour
    def test_the_collocations_come_back
        @store.keep_collocations("temperature", [found, found("b")])
        assert_equal [found, found("b")], sorted("temperature")
    end

    def test_they_are_kept_by_quantity
        @store.keep_collocations("temperature", [found])
        assert_empty @store.collocations("humidity")
    end

    def test_a_keep_replaces_the_same_location_and_regime
        @store.keep_collocations("temperature", [found, found("b")])
        again = found.with(samples: 900)
        @store.keep_collocations("temperature", [again])
        assert_equal [again, found("b")], sorted("temperature")
    end

    private

    def sorted(quantity)
        @store.collocations(quantity).sort_by { [it.location, it.regime] }
    end

    def found(location = "a")
        Sensorium::Collocation.new(location:, quantity: "temperature",
                                   regime: "winter",
                                   sigmas: { "ceil" => 0.12, "tado" => nil,
                                             "airzone" => 0.25 },
                                   samples: 5000)
    end
end

class MemoryStoreCollocationsTest < Minitest::Test
    include StoreCollocationsBehaviour

    def setup = @store = Sensorium::Store::Memory.new
end

class SequelStoreCollocationsTest < Minitest::Test
    include StoreCollocationsBehaviour

    def setup = @store = Sensorium::Store::Sequel.new(Sequel.sqlite)

    def test_the_table_can_be_named
        db = Sequel.sqlite
        Sensorium::Store::Sequel.new(db,
                                     tables: { collocations: :room_tc })
        assert db.table_exists?(:room_tc)
        refute db.table_exists?(:sensor_collocations)
    end
end
