# frozen_string_literal: true

require "test_helper"
require "support/winter"

# Learned.block_share: how much of a residual's spread survives
# averaging over three hours (18 bins of ten minutes), as the Tracker's
# CUSUM takes it.
class BlockShareTest < Minitest::Test
    SETUP = Sensorium::Presets.room
    DAYS  = 10

    # Independent bins: a block mean's spread is about 1/√18 of a bin's.
    def test_independent_residuals_average_away
        random = Random.new(3)
        share = share_of { random.rand - 0.5 }
        assert_in_delta 1 / Math.sqrt(18), share, 0.08
    end

    # An error that persists for hours (a daily swing): averaging over
    # three hours leaves most of it.
    def test_a_persistent_error_does_not
        share = share_of { |at| Math.sin(2 * Math::PI * at / 86_400.0) }
        assert_operator share, :>, 0.9
    end

    def test_too_few_blocks_give_none
        residuals = bins.first(9 * 18).to_h { [it, (it % 7) - 3.0] }
        assert_nil Sensorium::Learned.block_share(residuals, SETUP)
    end

    def test_a_learned_offset_carries_one
        offsets = Winter.learned.offsets
        assert(offsets.all? { it.block_share&.between?(0.0, 1.0) })
    end

    private

    def bins = (0...(DAYS * 144)).map { it * 600 }

    def share_of
        residuals = bins.to_h { [it, yield(it)] }
        Sensorium::Learned.block_share(residuals, SETUP)
    end
end
