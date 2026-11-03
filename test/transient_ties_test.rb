# frozen_string_literal: true

require "test_helper"

# A threshold is set by a target rate of false alarms: each window and
# direction leaves about transient_rate calm changes a day beyond it
# (README, Transients), "whatever the shape" (DESIGN.md, Transients),
# also for a sensor that reports in steps of 0.1.
class TransientTiesTest < Minitest::Test
    SETUP = Sensorium::Presets.room

    # Ten days of ten-minute changes of a sensor reporting in tenths:
    # mostly 0, twenty steps of 0.1 each way, two of 0.3 each way.
    def changes
        ([0.0] * 1396) + ([0.1] * 20) + ([-0.1] * 20) + [0.3, 0.3, -0.3, -0.3]
    end

    def test_a_stepped_sensor_has_about_the_target_rate_of_alarms
        threshold = Sensorium::Transient.threshold(changes, SETUP)
        allowed = SETUP.transient_rate * changes.size * SETUP.bin / 86_400.0
        %i[rise fall].each do |side|
            count = changes.count { threshold.beyond(it)&.first == side }
            assert_operator count, :<=, 2 * allowed, "#{side}s: #{count}"
        end
    end

    # Without ties (one change at each quantile), the thresholds are the
    # quantiles themselves, as before ties were raised.
    def test_untied_changes_keep_their_quantiles
        random = Random.new(5)
        untied = Array.new(1440) { random.rand - 0.5 }
        share = SETUP.transient_rate * SETUP.bin / 86_400.0
        expected = Sensorium::Transient::Threshold.new(
            fall: Sensorium::Stats.quantile(untied, share),
            rise: Sensorium::Stats.quantile(untied, 1 - share)
        )
        assert_equal expected, Sensorium::Transient.threshold(untied, SETUP)
    end
end
