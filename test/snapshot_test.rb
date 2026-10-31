# frozen_string_literal: true

require "test_helper"
require "support/fake_house"

# Snapshot.from a source: the latest readings, and the influences at the
# moment.
class SnapshotTest < Minitest::Test
    SETUP = Sensorium::Presets.room

    # 5 January 02:10: valves opened in room-a, every 20 min since
    # midnight; the latest reading is that of the moment.
    def test_the_heating_is_site_wide
        snap = at(FakeHouse::START + (2 * 3600) + 600)
        assert_equal %w[heating], snap.on("room-b")
        assert_equal 0, snap.age(snap.latest[%w[room-a tado]])
    end

    # The last opening is at 02:40.
    def test_the_heating_holds_an_hour_after_the_last_opening
        last = FakeHouse::START + (2 * 3600) + 2400
        assert_equal %w[heating], at(last + 3500).on("room-a")
        assert_empty at(last + 3601).on("room-a")
    end

    # The window's readings of each sensor, oldest first.
    def test_the_history_before_the_latest
        snap = at(FakeHouse::START + (3 * 3600))
        history = snap.history.fetch(%w[room-a ceil-a])
        assert_equal 19, history.size
        assert_equal snap.latest[%w[room-a ceil-a]], history.last
        assert_equal history.sort_by(&:time), history
    end

    # The humidity preset's creep looks seven hours back: the history
    # does, the latest readings stay within the window. few's tado was
    # last read 110 minutes before.
    def test_a_longer_history_leaves_the_latest_alone
        humidity = Sensorium::Presets.room(Sensorium::Presets::HUMIDITY)
        at = FakeHouse::START + (5 * 3600)
        snap = Sensorium::Snapshot.from(house, humidity, at:, window: 3600)
        refute snap.latest.key?(%w[few tado])
        assert_equal 20, snap.history.fetch(%w[few tado]).size
    end

    def test_the_aircon_holds_where_it_ran
        snap = at(FakeHouse::START + (2 * 86_400) + 3600)
        assert_equal [%w[aircon cooling]], snap.holding("room-a")
        assert_empty snap.holding("room-b")
    end

    # Named as the Learner names them, a "/" in a location or an
    # external's device included.
    def test_a_neighbour_is_found_by_the_learners_name
        latest = [["floor/1", "g1"], [nil, "meteo/lyon"], %w[garage g1]]
                 .to_h { |key| [key, reading(*key)] }
        snap = Sensorium::Snapshot.new(at: FakeHouse::START, latest:)
        latest.each_key do |key|
            name = Sensorium::Learner::Neighbours.name_of(*key)
            found = snap.neighbour(name)
            assert_equal key, [found.location, found.device]
        end
    end

    private

    def reading(location, device)
        Sensorium::Reading.new(time: FakeHouse::START, location:, device:,
                               value: 10.0)
    end

    def at(time) = Sensorium::Snapshot.from(house, SETUP, at: time)

    def house = (@house ||= FakeHouse.new)
end
