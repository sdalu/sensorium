# frozen_string_literal: true

require "test_helper"
require "sensorium/store/sequel"

# Names are Strings, as an SQL store gives them back: a Symbol given
# for an influence, a quantity or a regime must still match after a
# round-trip.
class NamesTest < Minitest::Test
    def test_influences_and_quantities_are_named_by_strings
        influence = Sensorium::Influence
        assert_equal "heating", influence::Switch.new(name: :heating).name
        assert_equal "aircon", influence::Mode.new(name: :aircon).name
        quantity = Sensorium::Quantity.new(name: :co2, sigma: 30, drift: 200)
        assert_equal "co2", quantity.name
    end

    def test_regimes_are_named_by_strings
        halves = Sensorium::Regime::Calendar.new(cold: [*10..12, *1..3],
                                                 warm: [*4..9])
        assert_equal "warm", halves.of(Time.new(2026, 6, 1))
        assert_equal %w[cold], halves.covered(Time.new(2026, 1, 1),
                                              Time.new(2026, 1, 2))
        assert_equal "all", Sensorium::Regime::Constant.new(:all).of(Time.now)
    end

    # The switch term applies after the SQL store, whatever it was named.
    def test_a_switch_term_survives_the_store
        store = Sensorium::Store::Sequel.new(Sequel.sqlite)
        store.keep(learned, from: Time.now, to: Time.now)
        offset = store.offsets("temperature").first
        assert_in_delta 20.0, offset.correct(20.5, on: [:heating]).value
        assert_in_delta 20.0, offset.correct(20.5, on: %w[heating]).value
    end

    private

    def learned
        offset = Sensorium::Offset.new(
            location: "a", device: "s", quantity: "temperature",
            regime: "winter", reference: "r", constant: 0.0,
            switches: { heating: 0.5 }, gain: nil, neighbour: nil,
            coefficient: nil, p10: -0.1, p90: 0.1, samples: 1000, plain: 0.0,
            plain_p10: -0.1, plain_p90: 0.1
        )
        Sensorium::Learned.new(quantity: "temperature", regimes: %w[winter],
                               offsets: [offset], shifts: [])
    end
end
