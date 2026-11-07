# frozen_string_literal: true

require "test_helper"

# Names are Strings (DESIGN.md, Stores and names): in what holds at the
# moment of a reading (Offset::Moment), a Series' value or a filtered
# Switch's exposure named by a Symbol is that of its String, not an
# unknown one. Every value is made up.
class MomentNamesTest < Minitest::Test
    # A Series' value and a filtered Switch's exposure named by a Symbol
    # are those of its String: the model, not the plain fallback.
    def test_symbol_names_in_a_moment
        strings = { values: { "solar" => 1000.0 },
                    exposures: { "heating" => 0.5 } }
        symbols = { values: { solar: 1000.0 }, exposures: { heating: 0.5 } }
        assert_equal offset.predict(20.0, **strings),
                     offset.predict(20.0, **symbols)
        assert_equal offset.correct(21.0, **strings),
                     offset.correct(21.0, **symbols)
    end

    private

    # 1 mK per W of sun, and 0.6 at full exposure to the radiators.
    def offset
        Sensorium::Offset.new(
            location: "l", device: "d", quantity: "temperature",
            regime: "all", reference: "r", constant: 0.0,
            switches: { "heating" => 0.6 }, taus: { "heating" => 1800 },
            series: { "solar" => 0.001 }, gain: nil, neighbour: nil,
            coefficient: nil, p10: -0.1, p90: 0.1, samples: 100, plain: 0.5,
            plain_p10: -0.2, plain_p90: 0.2
        )
    end
end
