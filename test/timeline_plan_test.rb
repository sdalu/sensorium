# frozen_string_literal: true

require "test_helper"

# The toolkit's binning without a Setup: a series summed per bin, and a
# Timeline made from influences alone, its levels and on-states by
# location. Every value is made up.
class TimelinePlanTest < Minitest::Test
    T0 = Time.utc(2026, 1, 5)
    HOUR = 3600

    VALVE  = Sensorium::Influence::Series.new(name: "valve",
                                              scope: :location, hold: 0)
    BURNER = Sensorium::Influence::Switch.new(name: "burner", hold: 0)

    # Each room's valve at 20 % then 60 %, the burner on in hour 1.
    Source = Struct.new(:events_by) do
        def events(name, from, to)
            events_by.fetch(name, []).select { (from..to).cover?(it.first) }
        end
    end

    def setup
        valve = %w[a b].flat_map do |room|
            [[T0, room, 20], [T0 + 1800, room, 20], [T0 + HOUR, room, 60]]
        end
        @source = Source.new({ "valve" => valve,
                               "burner" => [[T0 + HOUR, nil, 1]] })
        @timeline = Sensorium::Timeline.of([VALVE, BURNER], @source,
                                           from: T0, to: T0 + (2 * HOUR),
                                           bin: HOUR)
    end

    def test_a_series_level_by_location
        levels = @timeline.levels_of("valve")
        assert_equal %w[a b], levels.keys.sort
        assert_equal({ T0.to_i => 20.0, (T0 + HOUR).to_i => 60.0 },
                     levels["a"])
    end

    def test_a_switch_on_state_site_wide
        assert_equal Set[(T0 + HOUR).to_i], @timeline.on_of("burner")[nil]
    end

    def test_no_such_influence_is_nothing
        assert_empty @timeline.levels_of("solar")
        assert_empty @timeline.on_of("valve")
    end

    # A level told on change, weighted by how long each value held: 20
    # for the first half hour, 60 after, 40 over the hour; its events'
    # own mean would be 40 as well only by chance (here, 46.7).
    def test_a_level_told_on_change_is_weighted_by_time
        told = [[T0, 20], [T0 + 1800, 60], [T0 + 2700, 60]]
        source = Source.new({ "valve" => told.map { [it[0], "a", it[1]] } })
        weighted = Sensorium::Influence::Series.new(
            name: "valve", scope: :location, hold: HOUR, weighted: true
        )
        timeline = Sensorium::Timeline.of([weighted], source, from: T0,
                                                              to: T0 + HOUR,
                                                              bin: HOUR)
        assert_in_delta 40.0, timeline.levels_of("valve")["a"][T0.to_i]
    end

    # A value holds `hold` at most: past it, a bin is the mean of what
    # held, and one nothing held in is absent.
    def test_a_value_holds_no_longer_than_hold
        series = Sensorium::Series.new(HOUR)
        found = series.weighted([[0, 10.0], [1800, 30.0]], 900)
        assert_equal({ 0 => 20.0 }, found)
    end

    # Energy adds up: an hour's readings summed, the mean otherwise.
    def test_readings_summed_or_averaged_per_bin
        series = Sensorium::Series.new(HOUR)
        readings = [1.0, 2.0, 4.0].each_with_index.map do |value, i|
            Sensorium::Reading.new(time: T0 + (i * 1200), location: nil,
                                   device: "meter", value:)
        end
        assert_equal({ T0.to_i => 7.0 },
                     series.of(readings, total: true)[[nil, "meter"]])
        assert_in_delta 7.0 / 3, series.of(readings)[[nil, "meter"]][T0.to_i]
    end

    def test_series_added_bin_by_bin
        series = Sensorium::Series.new(HOUR)
        assert_equal({ 0 => 3.0, 3600 => 2.0 },
                     series.added([{ 0 => 1.0 }, { 0 => 2.0, 3600 => 2.0 }]))
    end
end
