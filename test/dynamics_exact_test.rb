# frozen_string_literal: true

require "test_helper"

# Dynamics::Model#change is the model's exact solution over any age:
# what stepping it bin by bin gives, not a straight line.
class DynamicsExactTest < Minitest::Test
    MODEL = Sensorium::Dynamics::Model.new(
        location: "room", quantity: "temperature", regime: "winter",
        a: 0.05, b: { "heating" => 0.2 }, c: 0.01, q: 0.04, bin: 600,
        steps: 1000
    )

    # Twenty bins (200 min), far past where a straight line holds.
    def test_the_change_is_the_model_stepped
        assert_in_delta stepped(20.0, 10.0, %w[heating], 20),
                        MODEL.change(20.0, 10.0, %w[heating], 20 / 6.0), 1e-9
        assert_in_delta stepped(20.0, 10.0, [], 7),
                        MODEL.change(20.0, 10.0, [], 7 / 6.0), 1e-9
    end

    # Long enough, the room settles where the inputs hold it.
    def test_a_long_age_settles_at_equilibrium
        settled = 10.0 + ((0.2 + 0.01) / 0.05)
        assert_in_delta settled - 20.0,
                        MODEL.change(20.0, 10.0, %w[heating], 1000), 1e-6
    end

    # Without an outside term, (b + c) per bin, exactly a line.
    def test_without_outside_a_line
        flat = MODEL.with(a: 0.0)
        assert_in_delta 0.21 * 12, flat.change(20.0, nil, %w[heating], 2.0)
    end

    private

    def stepped(value, outside, on, bins)
        bins.times.reduce(value) do |r, _|
            r + (0.05 * (outside - r)) + MODEL.switched(on) + 0.01
        end - value
    end
end
