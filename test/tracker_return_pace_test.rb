# frozen_string_literal: true

require "test_helper"

# The return CUSUM of a jumped track: "both above h, the error is within
# k of it, with the evidence a jump takes", "one block moves a side by
# h/2 at most, so no two blocks fill one" (README, Tracking). One block
# whose mean swings 5 σ the other way moves a side by h/2 at most, half
# of what a return takes, and an error 0.55 σ away, beyond k, is not
# back: the jump does not clear.
class TrackerReturnPaceTest < Minitest::Test
    QUANTITY = Sensorium::Presets.room.quantity
    AT = Time.utc(2026, 1, 10)
    STEP = Sensorium::Tracker::Step.new(QUANTITY, 0.1)
    OTHERS = [0.0, 0.0].each_with_index.map do |value, i|
        Sensorium::Parts::Part.new(device: "o#{i}", raw: value, value:,
                                   sigma: 0.1, age: 0, time: AT, note: nil)
    end

    # One reading every cusum_block: each closes the block of the one
    # before, so each block's standardised mean is the z given.
    def test_a_jump_does_not_clear_in_fewer_than_eleven_blocks
        track = jumped
        states = [5.0, -5.0, 0.55, 0.55, 0.55, 0.55, 0.55]
                 .each_with_index.map do |z, i|
            time = AT + (i * QUANTITY.cusum_block)
            track = STEP.call(track, part(z * scale, time), OTHERS, time)
            track.state
        end
        assert_equal [:jumped] * 7, states,
                     "cleared after #{states.index(:ok)} closed blocks"
    end

    private

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
