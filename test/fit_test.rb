# frozen_string_literal: true

require "test_helper"

# Fit on made-up bins: a reference swinging ±3 around 20, a neighbour
# ±5 around 10, a little noise, and the terms each sensor is built with.
class FitTest < Minitest::Test
    BINS = (0...1000).to_a
    # Two switches the sensor follows, and one it does not.
    A = BINS.select { it % 4 < 2 }.to_set
    B = BINS.select { (it % 3).zero? }.to_set
    C = BINS.first(500).to_set

    def setup
        @reference = BINS.to_h { [it, 20 + (3 * Math.sin(it / 50.0))] }
        @gaps = BINS.to_h { [it, @reference[it] - neighbour(it)] }
        @noise = noise
    end

    def test_a_sensor_reading_five_percent_high_earns_a_gain
        model = fit { |bin| 0.3 + (0.05 * @reference[bin]) }
        assert_in_delta 0.05, model.gain, 0.002
        assert_in_delta 0.3, model.constant, 0.05
        assert_nil model.neighbour
    end

    def test_no_gain_when_the_setup_says_so
        model = fit(gain: false) { |bin| 0.3 + (0.05 * @reference[bin]) }
        assert_nil model.gain
    end

    # Both at once: the gain and the neighbour fitted together.
    def test_a_gain_and_a_neighbour_together
        model = fit do |bin|
            0.3 + (0.05 * @reference[bin]) - (0.2 * @gaps[bin])
        end
        assert_equal "n", model.neighbour
        assert_in_delta 0.05, model.gain, 0.005
        assert_in_delta(-0.2, model.coefficient, 0.005)
    end

    def test_each_switch_the_sensor_follows_is_a_term
        model = switched
        assert_equal %w[a b], model.switches.keys.sort
        assert_in_delta 0.1, model.constant, 0.02
    end

    def test_the_switches_terms
        model = switched
        assert_in_delta 0.5, model.switches["a"], 0.02
        assert_in_delta 0.3, model.switches["b"], 0.02
    end

    private

    def neighbour(bin) = 10 + (5 * Math.cos(bin / 37.0))

    def noise
        random = Random.new(7)
        BINS.to_h { [it, (random.rand - 0.5) * 0.02] }
    end

    def switched
        fit(switches: { "a" => A, "b" => B, "c" => C }) do |bin|
            0.1 + (A.include?(bin) ? 0.5 : 0) + (B.include?(bin) ? 0.3 : 0)
        end
    end

    def fit(switches: {}, gain: true)
        diffs = BINS.to_h { [it, yield(it) + @noise[it]] }
        setup = Sensorium::Setup.new(quantity: Sensorium::Presets::TEMPERATURE,
                                     gain:)
        Sensorium::Fit.new(diffs, setup, levels: @reference, switches:,
                                         candidates: { "n" => @gaps }).model
    end
end
