# frozen_string_literal: true

require "test_helper"
require "support/airing_room"

# Transient::Detector: a change over a window, as the snapshot's
# history tells it, against the sensor's own thresholds, learned on
# AiringRoom's calm days.
class TransientDetectorTest < Minitest::Test
    START = AiringRoom::START
    SPAN  = AiringRoom::DAYS * 86_400
    STEP  = 720 # s steps up by 1 °C at this bin (day 5)
    SETUP = Sensorium::Setup.new(quantity: Sensorium::Presets::TEMPERATURE,
                                 places: %w[ceiling])

    def setup
        @house = AiringRoom.new(steps: { STEP => 1.0 })
        @profiles = Sensorium::Transient.learn(AiringRoom.new, SETUP,
                                               from: START, to: START + SPAN)
    end

    def test_a_step_is_an_event_at_its_z
        events = detector.events(at(STEP))
        assert_equal [600, 1200], events.map(&:window)
        events.each do |event|
            assert_equal ["room", "s", :rise, @house.time(STEP)],
                         event.to_h.values_at(:location, :device,
                                              :direction, :at)
            assert_in_delta expected(event.window), event.z, 1e-9
        end
    end

    def test_a_calm_sensor_has_no_event
        assert_empty detector.events(at(STEP - 100))
        assert_empty detector.events(at(STEP + 10))
    end

    # A step of 1 °C is some ten times the threshold.
    def test_z_is_the_change_over_its_threshold
        events = detector.events(at(STEP))
        assert(events.all? { it.z.between?(8, 13) })
    end

    def test_a_fall_is_said
        house = AiringRoom.new(steps: { STEP => -1.0 })
        events = detector.events(at(STEP, house))
        assert(events.all? { it.direction == :fall && it.z >= 1 })
        refute_empty events
    end

    # Without a reading at or before the window's start, no change.
    def test_a_history_short_of_the_window_says_nothing
        latest = @house.readings_at(STEP).to_h do |reading|
            [[reading.location, reading.device], reading]
        end
        history = latest.transform_values { [it] }
        snapshot = Sensorium::Snapshot.new(at: @house.time(STEP), latest:,
                                           history:)
        assert_empty detector.events(snapshot)
    end

    def test_a_snapshot_reaches_back_for_the_longest_window
        assert_equal 1200 + SETUP.carry, Sensorium::Snapshot::Gather.reach(SETUP)
    end

    # s steps, then falls silent; two hours later its last reading is
    # past max_age, and so is its event.
    def test_a_reading_past_max_age_is_no_event
        silent = Silent.new(@house)
        assert_empty detector.events(at(STEP + 12, silent))
        refute_empty detector.events(at(STEP + 3, silent))
    end

    # The house with s's readings cut after its step.
    class Silent < SimpleDelegator
        def readings(quantity, from, to, devices = nil)
            cut = __getobj__.time(STEP)
            super.reject { it.device == "s" && it.time > cut }
        end
    end

    private

    def detector
        Sensorium::Transient::Detector.new(SETUP, profiles: @profiles)
    end

    def profile(device) = @profiles.find { it.device == device }

    def at(index, house = @house)
        Sensorium::Snapshot.from(house, SETUP, at: house.time(index))
    end

    # z as the readings make it: s's change over the window, over its
    # rise threshold.
    def expected(window)
        value = ->(index) { @house.readings_at(index).last.value }
        change = value[STEP] - value[STEP - (window / 600)]
        change / profile("s").own[window].rise
    end
end
