# frozen_string_literal: true

require "test_helper"

# Learned.block_share groups the residuals in whole blocks of
# cusum_block, given as an Integer or as a Float (1.5 h as 1.5 * 3600):
# a bin divided by a Float is no block number, each bin would be a block
# of its own, and the share nil.
class BlockShareFloatTest < Minitest::Test
    def test_a_float_block_gives_the_same_share_as_its_integer
        residuals = persistent
        shares = [5400, 1.5 * 3600].map do |block|
            quantity = Sensorium::Quantity.new(name: "t", sigma: 0.1,
                                               drift: 1.0,
                                               cusum_block: block)
            Sensorium::Learned.block_share(residuals,
                                           Sensorium::Setup.new(quantity:))
        end
        refute_nil shares.first
        assert_equal shares.first, shares.last
    end

    private

    # An AR(1) of 0.9, ten-minute bins, two weeks.
    def persistent
        random = Random.new(1)
        x = 0.0
        (0...2000).to_h do |i|
            x = (0.9 * x) + random.rand - 0.5
            [1_699_999_800 + (i * 600), x]
        end
    end
end
