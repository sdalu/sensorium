# frozen_string_literal: true

require "test_helper"

# The return CUSUM of a jumped track clears a part back at its delta at
# the pace of k a block: "both above h, the error is within k of it,
# with the evidence a jump takes ... That takes eleven blocks (33 h) at
# least" (README, Tracking). Its block means are never all at zero: they
# scatter around it by one σ, and the sides must still climb by k a
# block on average, so the clear comes within a few blocks of eleven,
# not after days.
class TrackerReturnNoiseTest < Minitest::Test
    QUANTITY = Sensorium::Presets.room.quantity
    AT = Time.utc(2026, 1, 10)
    STEP = Sensorium::Tracker::Step.new(QUANTITY, 0.1)
    OTHERS = [0.0, 0.0].each_with_index.map do |value, i|
        Sensorium::Parts::Part.new(device: "o#{i}", raw: value, value:,
                                   sigma: 0.1, age: 0, time: AT, note: nil)
    end

    # Block means scattered around zero as N(0, 1) draws are (a seeded
    # sequence, kept as values): mean 0.23, sd 0.86 over the 24.
    BACK = [-0.68, 0.66, -0.32, -0.29, 0.27, -0.13, -0.06, 0.65,
            1.66, -0.46, -0.65, -0.74, -0.91, 1.19, 2.26, 0.42,
            0.11, -0.06, 0.82, -1.15, 0.83, 0.88, -0.12, 1.37].freeze

    # One reading every cusum_block: each closes the block of the one
    # before, so reading i closes block i - 1 at the z given, and the
    # state after reading i is the test's after i closed blocks.
    def test_a_noisy_return_clears_in_about_eleven_blocks
        cleared = states(BACK).index(:ok)
        refute_nil cleared, "still jumped after #{BACK.size - 1} closed blocks"
        assert_operator cleared, :<=, 16,
                        "cleared after #{cleared} blocks, not about eleven"
    end

    private

    # The track's state after each reading, the block means given.
    def states(zs)
        track = jumped
        zs.each_with_index.map do |z, i|
            time = AT + (i * QUANTITY.cusum_block)
            track = STEP.call(track, part(z * scale, time), OTHERS, time)
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

    # What a block's mean innovation is standardised by.
    def scale
        _, spread, = Sensorium::Combine.robust(OTHERS, QUANTITY.robust_nu)
        Math.sqrt(0.01 + (0.1**2) + (spread**2))
    end
end
