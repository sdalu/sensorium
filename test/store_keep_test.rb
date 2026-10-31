# frozen_string_literal: true

require "test_helper"
require "sensorium/store/sequel"
require "support/winter"

# What a learning replaces in each store: a sensor learned again, and
# every sensor of a location whose reference changed; nothing of a
# location or regime it learned nothing in.
module StoreKeepBehaviour
    WINTER = Winter.learned

    def test_a_sensor_learned_again_is_replaced
        keep(WINTER)
        keep(again(WINTER.offsets.first.with(constant: 9.0)))
        assert_in_delta 9.0, find(WINTER.offsets.first).constant
        assert_equal WINTER.offsets.size, @store.offsets("temperature").size
    end

    # The other sensors' offsets stay, and their shifts.
    def test_a_sensor_short_of_samples_keeps_its_offset
        keep(WINTER)
        keep(again(WINTER.offsets.first))
        assert_equal WINTER.offsets.size, @store.offsets("temperature").size
    end

    def test_only_the_shifts_of_a_sensor_learned_again_go
        first = WINTER.offsets.first
        keep(WINTER)
        keep(again(first))
        assert_equal WINTER.shifts.size - shifts_of(first),
                     @store.shifts("temperature").size
    end

    def test_a_new_reference_replaces_the_location
        keep(WINTER)
        keep(again(WINTER.offsets.first.with(reference: "plain-a")))
        location = WINTER.offsets.first.location
        kept = @store.offsets("temperature").select do |offset|
            offset.location == location
        end
        assert_equal %w[plain-a], kept.map(&:reference).uniq
    end

    # Late March into April: a mid season with nothing learned in it.
    def test_a_regime_barely_touched_is_kept
        keep(WINTER.with(regimes: %w[mid],
                         offsets: WINTER.offsets.map { it.with(regime: "mid") },
                         shifts: []))
        keep(WINTER.with(regimes: %w[winter mid]))
        assert_equal %w[mid winter],
                     @store.offsets("temperature").map(&:regime).uniq.sort
    end

    def test_a_regime_is_learned_when_it_has_offsets
        keep(WINTER.with(regimes: %w[winter summer]))
        assert_equal %w[winter], @store.learned("temperature").keys
    end

    private

    def again(offset)
        WINTER.with(offsets: [offset], shifts: [])
    end

    def find(offset)
        key = Sensorium::Learned.key(offset)
        @store.offsets("temperature").find { Sensorium::Learned.key(it) == key }
    end

    def shifts_of(offset)
        WINTER.shifts.count do |shift|
            shift.location == offset.location && shift.device == offset.device
        end
    end

    def keep(learned)
        @store.keep(learned, from: FakeHouse::START, to: FakeHouse::START,
                             at: FakeHouse::START)
    end
end

class MemoryStoreKeepTest < Minitest::Test
    include StoreKeepBehaviour

    def setup = @store = Sensorium::Store::Memory.new
end

class SequelStoreKeepTest < Minitest::Test
    include StoreKeepBehaviour

    def setup = @store = Sensorium::Store::Sequel.new(Sequel.sqlite)
end
