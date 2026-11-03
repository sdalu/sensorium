# frozen_string_literal: true

require "test_helper"

# The return test reads a block mean within ±(h/2 − k) of zero, so that
# "one block moves a side by h/2 at most", and "a side climbs only while
# the error is back on its side of the delta held" (README, Tracking):
# up += k − z holds up down only while the clip leaves z at k or more,
# which takes h/2 − k ≥ k. The two hold together only with cusum_h at
# least 4 cusum_k, and a Quantity below that is refused: with h < 4k
# every block climbs both sides, wherever the error is, and with h < 2k
# the clip's bounds cross and Comparable#clamp raises at the first
# closed block of a jumped track.
class TrackerReturnSwingTest < Minitest::Test
    AT = Time.utc(2026, 1, 10)
    QUANTITY = Sensorium::Presets.room.quantity

    def test_a_quantity_with_cusum_h_below_4_cusum_k_is_refused
        error = assert_raises(ArgumentError) do
            QUANTITY.with(cusum_k: 1.0, cusum_h: 3.0)
        end
        assert_match(/cusum_h/, error.message)
        assert_raises(ArgumentError) do
            Sensorium::Quantity.new(name: "t", sigma: 0.1, drift: 1.0,
                                    cusum_k: 0.5, cusum_h: 0.8)
        end
    end

    def test_cusum_h_at_4_cusum_k_is_the_least_accepted
        assert_equal 4.0, QUANTITY.with(cusum_k: 1.0, cusum_h: 4.0).cusum_h
        assert_equal 5.0, QUANTITY.cusum_h
    end

    # k = 1, h = 4 (a CUSUM tuned for a 2 σ shift, at the bound): the
    # error stays 6 block σ away from the delta held, every block; the
    # track stays jumped, the up side held at 0 by the clip at k.
    def test_an_error_still_away_stays_jumped_at_the_bound
        quantity = QUANTITY.with(cusum_k: 1.0, cusum_h: 4.0)
        states = states(quantity, Array.new(20, 6.0))
        assert_equal [:jumped], states.uniq,
                     "cleared at block #{states.index(:ok)} though the " \
                     "error never came back"
    end

    private

    def others
        [0.0, 0.0].each_with_index.map do |value, i|
            Sensorium::Parts::Part.new(device: "o#{i}", raw: value, value:,
                                       sigma: 0.1, age: 0, time: AT,
                                       note: nil)
        end
    end

    # One reading every cusum_block, each closing the block before at
    # about the z given; the state after each.
    def states(quantity, zs)
        step = Sensorium::Tracker::Step.new(quantity, 0.1)
        track = jumped
        zs.each_with_index.map do |z, i|
            time = AT + (i * quantity.cusum_block)
            track = step.call(track, part(z * scale(quantity), time),
                              others, time)
            track.state
        end
    end

    def part(value, time)
        Sensorium::Parts::Part.new(device: "s", raw: value, value:,
                                   sigma: 0.1, age: 0, time:, note: nil)
    end

    def jumped
        Sensorium::Track.start(location: "room", device: "s",
                               quantity: "temperature", regime: "winter",
                               reference: "ceil", variance: 0.01)
                        .with(state: :jumped)
    end

    def scale(quantity)
        _, spread, = Sensorium::Combine.robust(others, quantity.robust_nu)
        Math.sqrt(0.01 + (0.1**2) + (spread**2))
    end
end
