# frozen_string_literal: true

require "test_helper"
require "support/fusion_helpers"

# A whole-number reading (a CO₂ sensor's ppm, say) with a whole-number
# delta: the age's cap delta² / 3 is a third of a variance, not an
# integer division of one.
class IntegerDeltaTest < Minitest::Test
    include FusionHelpers

    # 50 minutes old: drift 1 °C/h gives 0.83², the delta 1²/3 = 0.33.
    def test_a_whole_number_delta_caps_at_a_third_of_its_square
        fused = fuse({ "ceil" => [20, 3000] },
                     locations: { "room" => Sensorium::Location.new(
                         name: "room", deltas: { "ceil" => 1 }
                     ) })
        assert_in_delta Math.sqrt((0.1**2) + (1 / 3.0)),
                        part(fused, "ceil").part.sigma, 1e-9
    end
end
