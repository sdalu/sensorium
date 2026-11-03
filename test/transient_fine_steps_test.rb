# frozen_string_literal: true

require "test_helper"

# A sensor stepping by 1e-4: a raise of a millionth of its step would
# fall within the grid changes are compared at (DIGITS), so a raise
# moves at least two units of it, and a single step is no event, a tie
# left out, as for a coarser sensor.
class TransientFineStepsTest < Minitest::Test
    SETUP = Sensorium::Presets.room
    STEP = 20.0001 - 20.0
    OTHER = 20.1499 - 20.15 # the same step, read apart
    LARGER = [-4.1, -2.7, -2.5, -1.9, -1.2, -1.2].map { it * STEP }.freeze

    def test_a_single_fine_step_is_no_event
        changes = ([0.0] * 1400) + [STEP, -STEP]
        threshold = Sensorium::Transient.threshold(changes, SETUP)
        assert_nil threshold.beyond(STEP), "rise #{threshold.rise}"
        assert_nil threshold.beyond(-STEP), "fall #{threshold.fall}"
        assert threshold.beyond(2 * STEP)
    end

    # Six falls of one fine step, read as two floats, past six larger
    # ones with six allowed: left out together, the larger ones beyond.
    def test_fine_ties_are_left_out_together
        threshold = Sensorium::Transient.threshold(tied, SETUP)
        assert_nil threshold.beyond(-STEP), "fall #{threshold.fall}"
        assert_nil threshold.beyond(OTHER), "fall #{threshold.fall}"
        LARGER.each { assert threshold.beyond(it) }
    end

    private

    def tied
        ([0.0] * 4300) + LARGER + [-STEP] + ([OTHER] * 5) + ([STEP / 5] * 6)
    end
end
