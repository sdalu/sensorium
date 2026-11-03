# frozen_string_literal: true

require "test_helper"

# Fit::Validated.confirmed bounds the inflation with the narrowings in
# the gap's space, while a correction (and its width) is the gap's over
# |1 + gain + k| (Offset#correct), the space Fit#ratio and
# HeldOut#keeps? judge a term in. README: "its σ is the plain
# constant's narrowed by what the bins it never saw bear out".
class ConfirmedSpaceTest < Minitest::Test
    BINS = (0...200).to_a
    PLAIN = BINS.to_h { [it, Math.sin(it / 7.0)] }

    # k = +0.6 (scale 1.6): the refit narrows the gap to 90 % (the
    # correction to 56 %); the bins held out leave the gap 120 % wide
    # (the correction 75 %, which HeldOut#keeps? accepts). The widened
    # correction must be 75 % of the plain constant's, not 62.5 %.
    def test_a_positive_k_is_widened_as_the_bins_held_out_confirm
        model = model(0.6, 0.9)
        inflation = confirmed(model, 1.2)
        width = model.spread * inflation / model.scale
        assert_in_delta 0.75 * plain.spread, width, 1e-9
    end

    # k = -0.4 (scale 0.6): the gap narrowed to 50 % (the correction to
    # 83 %), the bins held out leave the gap 80 % (the correction 133 %,
    # wider than its fallback). The bound the comment states: no wider
    # than the plain constant's.
    def test_a_negative_k_is_widened_no_further_than_the_constant
        model = model(-0.4, 0.5)
        inflation = confirmed(model, 0.8)
        width = model.spread * inflation / model.scale
        assert_operator width, :<=, plain.spread + 1e-9
    end

    private

    def plain = @plain ||= fitted(PLAIN, nil, nil)

    def model(coefficient, narrowing)
        fitted(PLAIN.transform_values { it * narrowing }, "n", coefficient)
    end

    def fitted(residuals, neighbour, coefficient)
        Sensorium::Fit::Model.new(constant: 0.0, switches: {}, taus: {},
                                  series: {}, gain: nil, neighbour:,
                                  coefficient:, rate: nil, residuals:)
    end

    def confirmed(model, held)
        fit = Struct.new(:plain).new(plain)
        Sensorium::Fit::Validated.confirmed(fit, model, held)
    end
end
