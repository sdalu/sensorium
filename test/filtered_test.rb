# frozen_string_literal: true

require "test_helper"

# A Switch with a time constant: its exposure is a first-order filter of
# its on-state, and the term is term × exposure, its tau chosen from the
# data. Every value is made up.
class FilteredTest < Minitest::Test
    BINS   = (0...1000).to_a
    SERIES = Sensorium::Series.new(600)
    SETUP  = Sensorium::Setup.new(quantity: Sensorium::Presets::TEMPERATURE)
    TAUS   = Sensorium::Influence::TAUS

    def setup
        @on = BINS.select { (it / 12).even? }.to_set { it * 600 }
        @exposures = TAUS.to_h do |tau|
            [tau, SERIES.filtered(@on, 0, 999 * 600, tau)]
        end
        random = Random.new(13)
        @noise = BINS.to_h { [it * 600, (random.rand - 0.5) * 0.02] }
    end

    def test_a_switch_has_no_time_constant_unless_given
        heating = Sensorium::Influence::Switch.new(name: "heating")
        assert_nil heating.tau
        assert_empty heating.taus
        assert_equal TAUS, heating.with(tau: TAUS).taus
    end

    # x += (on - x) × (1 - exp(-bin / tau)), from 0.
    def test_the_exposure_is_a_first_order_filter
        keep = Math.exp(-1.0)
        found = SERIES.filtered(Set[0, 600], 0, 1800, 600)
        assert_in_delta 1 - keep, found[0]
        assert_in_delta 1 - (keep**2), found[600]
        assert_in_delta (1 - (keep**2)) * (keep**2), found[1800]
    end

    # Long after the Switch was last on (a summer after the heating),
    # nothing: not a tail of tiny values a slope would blow up on.
    def test_an_exposure_long_off_is_nothing
        found = SERIES.filtered(Set[0], 0, 600 * 3000, 7200)
        assert_equal 0.0, found.fetch(600 * 3000)
    end

    def test_the_time_constant_that_fits_is_chosen
        model = fit { 0.1 + (0.5 * @exposures[1800][it]) }
        assert_equal({ "heating" => 1800 }, model.taus)
        assert_in_delta 0.5, model.switches.fetch("heating"), 0.02
    end

    def test_a_sensor_the_switch_does_not_move_earns_none
        model = fit { 0.1 }
        assert_empty model.switches
        assert_empty model.taus
    end

    # 0.2 + 1.0 × an exposure of 0.25.
    def test_the_exposure_is_solved_for
        found = offset.correct(20.45, exposures: { "heating" => 0.25 })
        assert_in_delta 20.0, found.value
    end

    private

    def fit
        diffs = @noise.to_h { |bin, n| [bin, yield(bin) + n] }
        levels = diffs.transform_values { 20.0 }
        Sensorium::Fit.new(diffs, SETUP, levels:,
                                         filtered: { "heating" => @exposures })
                      .model
    end

    def offset
        Sensorium::Offset.new(location: "a", device: "s",
                              quantity: "temperature", regime: "winter",
                              reference: "r", constant: 0.2,
                              switches: { "heating" => 1.0 },
                              taus: { "heating" => 1800 }, gain: nil,
                              neighbour: nil, coefficient: nil, p10: -0.1,
                              p90: 0.1, samples: 1000, plain: 0.6,
                              plain_p10: -0.5, plain_p90: 0.5)
    end
end
