# frozen_string_literal: true

require "test_helper"
require "support/fake_house"

# Learner on a constructed house (FakeHouse): what each sensor's offset
# comes out as, and which terms it earns.
class LearnerTest < Minitest::Test
    START = FakeHouse::START
    SPAN  = FakeHouse::DAYS * 86_400

    def setup
        @house = FakeHouse.new
        @learned = learner(@house).learn
        @found = @learned.offsets.to_h { [[it.location, it.device], it] }
    end

    def test_a_constant_offset_earns_no_term
        tado = @found.fetch(%w[room-a tado])
        assert_in_delta(-0.9, tado.constant, 0.03)
        assert_empty tado.switches
        assert_nil tado.gain
        assert_nil tado.neighbour
        assert_operator tado.p90 - tado.p10, :<, 0.2
    end

    def test_an_offset_says_what_it_is_against
        tado = @found.fetch(%w[room-a tado])
        assert_equal "ceil-a", tado.reference
        assert_equal "temperature", tado.quantity
        assert_equal "winter", tado.regime
    end

    # The aircon's 30 hours, 5 °C off, are left out: nothing spreads them.
    def test_the_heating_is_a_term_and_the_aircon_left_out
        airzone = @found.fetch(%w[room-a airzone])
        assert_in_delta 1.1, airzone.constant, 0.03
        assert_in_delta 0.5, airzone.switches.fetch("heating"), 0.05
        assert_nil airzone.neighbour
        assert_operator airzone.p90, :<, 0.2
    end

    # Learned apart, on the constant alone: airzone reads 5 °C over the
    # reference meanwhile, tado as ever.
    def test_the_aircon_is_a_shift_per_mode
        assert_equal [%w[airzone cooling], %w[plain-a cooling],
                      %w[tado cooling]], shifts.keys.sort
        assert(shifts.values.all? { it.influence == "aircon" })
    end

    def test_the_aircon_shift_is_over_the_plain_offset
        airzone = shifts[%w[airzone cooling]]
        assert_in_delta 5.0 - @found[%w[room-a airzone]].plain,
                        airzone.shift, 0.01
        assert_equal 180, airzone.samples
    end

    def test_a_sensor_the_aircon_misses_has_no_shift
        tado = @learned.shifts.find { it.device == "tado" }
        assert_in_delta 0.0, tado.shift, 0.05
    end

    def test_a_floor_sensor_is_a_reference_and_the_garage_a_neighbour
        airzone = @found.fetch(%w[room-b airzone])
        assert_equal "leak-b", airzone.reference
        assert_equal "garage/g1", airzone.neighbour
        assert_in_delta(-0.3, airzone.coefficient, 0.02)
        assert_in_delta 0.4, airzone.constant, 0.1
    end

    def test_no_reference_and_too_few_samples_give_nothing
        assert_equal [%w[room-a airzone], %w[room-a plain-a],
                      %w[room-a tado], %w[room-b airzone]], @found.keys.sort
    end

    # Late March into April: winter and mid-season, learned apart.
    def test_each_regime_is_learned_apart
        learned = spring
        assert_equal %w[winter mid], learned.regimes
        tado = learned.offsets.select do |offset|
            offset.location == "room-a" && offset.device == "tado"
        end
        assert_equal(%w[mid winter], tado.map(&:regime).sort)
        assert(tado.all? { (it.constant + 0.9).abs < 0.05 })
    end

    def test_only_the_sensors_are_read
        assert_equal %w[airzone ceil-a ceil-f g1 leak-b plain-a plain-blue
                        tado], @house.queried.sort
    end

    private

    def shifts = @learned.shifts.to_h { [[it.device, it.mode], it] }

    # Ten days from 27 March.
    def spring
        start = Time.utc(2026, 3, 27)
        learner(FakeHouse.new(start:), from: start).learn
    end

    def learner(house, from: START, locations: {})
        Sensorium::Learner.new(house, Sensorium::Presets.room,
                               from:, to: from + SPAN, locations:)
    end
end
