# frozen_string_literal: true

require "test_helper"
require "sensorium/store/sequel"

# Transient profiles come back from each store as kept; a later keep
# replaces those of the same location, device and regime only.
module StoreTransientsBehaviour
    def test_the_profiles_come_back
        @store.keep_transients("temperature", [found, found("airzone")])
        assert_equal [found("airzone"), found], sorted("temperature")
    end

    def test_they_are_kept_by_quantity
        @store.keep_transients("temperature", [found])
        assert_empty @store.transients("humidity")
    end

    def test_a_keep_replaces_the_same_location_device_and_regime
        @store.keep_transients("temperature",
                               [found, found("airzone"),
                                found.with(regime: "mid")])
        again = found.with(relative: {})
        @store.keep_transients("temperature", [again])
        assert_equal [found("airzone"), found.with(regime: "mid"), again],
                     sorted("temperature")
    end

    private

    def sorted(quantity)
        @store.transients(quantity)
              .sort_by { [it.location, it.device, it.regime] }
    end

    def found(device = "tado")
        scale = Sensorium::Transient::Scale
        Sensorium::Transient::Profile.new(
            location: "room", device:, quantity: "temperature",
            regime: "winter",
            own: { 600 => scale.new(sigma: 0.0421, median: -0.01),
                   1200 => scale.new(sigma: 0.0613, median: 0.0) },
            relative: { 600 => scale.new(sigma: 0.05, median: 0.002) }
        )
    end
end

class MemoryStoreTransientsTest < Minitest::Test
    include StoreTransientsBehaviour

    def setup = @store = Sensorium::Store::Memory.new
end

class SequelStoreTransientsTest < Minitest::Test
    include StoreTransientsBehaviour

    def setup = @store = Sensorium::Store::Sequel.new(Sequel.sqlite)

    def test_the_table_can_be_named
        db = Sequel.sqlite
        Sensorium::Store::Sequel.new(db, tables: { transients: :room_tr })
        assert db.table_exists?(:room_tr)
        refute db.table_exists?(:sensor_transients)
    end
end
