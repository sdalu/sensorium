# frozen_string_literal: true

require "test_helper"
require "sensorium/store/sequel"
require "support/fake_house"

# The same behaviour from each store: a learning replaces the regimes it
# covers, an Offset comes back as kept, settings are set and reset.
module StoreBehaviour
    # Learned once, for every store.
    def self.learned
        @learned ||= Sensorium::Learner.new(
            FakeHouse.new, Sensorium::Presets.room,
            from: FakeHouse::START, to: FakeHouse::START + (10 * 86_400)
        ).learn
    end

    def test_a_learning_comes_back
        keep(learned)
        assert_equal sorted(learned.offsets),
                     sorted(@store.offsets("temperature"))
        assert_equal learned.shifts.size, @store.shifts("temperature").size
    end

    def test_a_learning_is_kept_by_quantity_and_regime
        keep(learned)
        assert_empty @store.offsets("humidity")
        assert_equal %w[winter], @store.learned("temperature").keys
    end

    def test_a_learning_keeps_the_regimes_it_does_not_cover
        keep(learned)
        keep(learned.with(regimes: %w[summer], offsets: [], shifts: []))
        refute_empty @store.offsets("temperature")
    end

    def test_a_learning_replaces_the_regimes_it_covers
        keep(learned)
        keep(learned.with(offsets: learned.offsets.first(1), shifts: []))
        assert_equal 1, @store.offsets("temperature").size
        assert_empty @store.shifts("temperature")
    end

    def test_a_location_is_set_and_reset
        @store.set_location("temperature", "blue",
                            { references: %w[a b], sigma: 0.2 })
        blue = @store.locations("temperature").fetch("blue")
        assert_equal %w[a b], blue.references
        assert_in_delta 0.2, blue.sigma
        @store.set_location("temperature", "blue", { sigma: nil })
        blue = @store.locations("temperature").fetch("blue")
        assert_nil blue.sigma
        assert_equal %w[a b], blue.references
        assert_empty @store.locations("humidity")
    end

    private

    def learned = StoreBehaviour.learned

    def keep(learned)
        @store.keep(learned, from: FakeHouse::START, to: FakeHouse::START,
                             at: FakeHouse::START)
    end

    def sorted(offsets)
        offsets.sort_by { [it.location, it.device, it.regime] }
    end
end

class MemoryStoreTest < Minitest::Test
    include StoreBehaviour

    def setup = @store = Sensorium::Store::Memory.new
end

class SequelStoreTest < Minitest::Test
    include StoreBehaviour

    def setup
        @store = Sensorium::Store::Sequel.new(Sequel.sqlite)
    end

    def test_the_tables_can_be_named
        db = Sequel.sqlite
        Sensorium::Store::Sequel.new(db, tables: { locations: :sensor_rooms })
        assert db.table_exists?(:sensor_rooms)
        refute db.table_exists?(:sensor_locations)
    end
end
