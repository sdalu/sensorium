# frozen_string_literal: true

require "test_helper"

# A Calendar's months are the site's, in the process's local zone: a
# History names a bin's regime from Time.at(bin), local, and the Fusion
# names a snapshot's from its at, which may be in UTC (as a Store reads
# times back). 22:30 UTC on 2026-03-31 is already April in Paris.
class RegimeZoneTest < Minitest::Test
    AT = Time.utc(2026, 3, 31, 22, 30)

    def test_learning_and_fusion_take_the_same_regime_of_an_instant
        with_tz("Europe/Paris") do
            setup = Sensorium::Presets.room
            history = Sensorium::History.new(
                setup, [AT - 3600, AT], sensors: [], readings: [],
                                        locations: {}, externals: {}
            )
            assert_equal "mid", history.regime_of(AT.to_i)
            assert_equal "mid", setup.regime.of(AT)
        end
    end

    def test_a_span_in_utc_covers_the_local_months
        with_tz("Europe/Paris") do
            assert_equal ["mid"],
                         Sensorium::Regime::Calendar.new.covered(AT, AT + 60)
        end
    end

    private

    def with_tz(name)
        before = ENV.fetch("TZ", nil)
        ENV["TZ"] = name
        yield
    ensure
        ENV["TZ"] = before
    end
end
