# frozen_string_literal: true

require "test_helper"
require "support/renamed_store"
require "sensorium/store/sequel"

# A location's Dynamics::Models come back from each store as kept; a
# later keep replaces those of the same location and regime only.
module StoreDynamicsBehaviour
    def test_the_models_come_back
        @store.keep_dynamics("temperature", [model, model("b")])
        assert_equal [model, model("b")], sorted("temperature")
    end

    def test_they_are_kept_by_quantity
        @store.keep_dynamics("temperature", [model])
        assert_empty @store.dynamics("humidity")
    end

    def test_a_keep_replaces_the_same_location_and_regime
        @store.keep_dynamics("temperature", [model, model("b")])
        again = model.with(a: 0.2, b: {})
        @store.keep_dynamics("temperature", [again])
        assert_equal [again, model("b")], sorted("temperature")
    end

    private

    def sorted(quantity)
        @store.dynamics(quantity).sort_by { [it.location, it.regime] }
    end

    def model(location = "a")
        Sensorium::Dynamics::Model.new(location:, quantity: "temperature",
                                       regime: "winter", a: 0.01,
                                       b: { "heating" => 0.05 }, c: -0.002,
                                       q: 0.003, bin: 600, steps: 20_000,
                                       rms_hold: 0.4, rms_model: 0.35)
    end
end

class MemoryStoreDynamicsTest < Minitest::Test
    include StoreDynamicsBehaviour

    def setup = @store = Sensorium::Store::Memory.new
end

class SequelStoreDynamicsTest < Minitest::Test
    include StoreDynamicsBehaviour

    def setup = @store = Sensorium::Store::Sequel.new(Sequel.sqlite)

    def test_the_table_can_be_named
        db = Sequel.sqlite
        Sensorium::Store::Sequel.new(db, tables: { dynamics: :room_dynamics })
        assert db.table_exists?(:room_dynamics)
        refute db.table_exists?(:sensor_dynamics)
    end
end

class RenamedStoreDynamicsTest < Minitest::Test
    include StoreDynamicsBehaviour

    def setup = @store = RenamedStore.new
end
