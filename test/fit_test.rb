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

    # A neighbour that covers only the calm bins, and follows nothing:
    # it would narrow the spread only by leaving the rough bins out.
    def test_a_neighbour_is_judged_on_the_bins_it_covers
        rough = BINS.last(190).to_set
        random = Random.new(3)
        gaps = BINS.first(810).to_h { [it, random.rand * 10] }
        model = fit(gain: false, candidates: { "n" => gaps }) do |bin|
            rough.include?(bin) ? 5 + Math.sin(bin) : 0.0
        end
        assert_nil model.neighbour
    end

    # Followed exactly, but seen on half the bins only.
    def test_a_neighbour_must_cover_most_bins
        half = @gaps.select { |bin, _| bin.even? }
        model = fit(candidates: { "n" => half }) { -0.2 * @gaps[it] }
        assert_nil model.neighbour
    end

    # Followed, on for 200 bins: enough to narrow, short of 300.
    def test_a_switch_needs_enough_bins_on
        few = BINS.first(200).to_set
        model = fit(switches: { "few" => few }, min_part: 300) do |bin|
            few.include?(bin) ? 3.0 : 0.0
        end
        assert_empty model.switches
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

    def fit(switches: {}, candidates: { "n" => @gaps }, **settings)
        diffs = BINS.to_h { [it, yield(it) + @noise[it]] }
        setup = Sensorium::Setup.new(quantity: Sensorium::Presets::TEMPERATURE,
                                     **settings)
        Sensorium::Fit.new(diffs, setup, levels: @reference, switches:,
                                         candidates:).model
    end
end
