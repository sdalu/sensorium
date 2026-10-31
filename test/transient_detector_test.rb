# frozen_string_literal: true

require "test_helper"
require "support/airing_room"

# Transient::Detector: a change over a window, as the snapshot's
# history tells it, standardised by the sensor's own scale.
class TransientDetectorTest < Minitest::Test
    START = AiringRoom::START
    SPAN  = AiringRoom::DAYS * 86_400
    STEP  = 720 # s steps up by 1 °C at this bin (day 5)
    SETUP = Sensorium::Setup.new(quantity: Sensorium::Presets::TEMPERATURE,
                                 places: %w[ceiling])

    def setup
        @house = AiringRoom.new(steps: { STEP => 1.0 })
        @profiles = Sensorium::Transient.learn(@house, SETUP, from: START,
                                                              to: START + SPAN)
    end

    # Learned over the step too: a few changes out of 1440 move a median
    # absolute deviation little.
    def test_a_step_leaves_the_scale_as_the_noise_makes_it
        sigma = profile("s").own[600].sigma
        assert_in_delta 1.4826 * 0.1 * (1 - Math.sqrt(0.5)), sigma, 0.005
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

    # 1 °C over σ 0.04 is a z of some 23.
    def test_an_event_needs_transient_z
        setup = SETUP.with(transient_z: 30)
        detector = Sensorium::Transient::Detector.new(setup,
                                                      profiles: @profiles)
        assert_empty detector.events(at(STEP))
    end

    def test_a_fall_is_said
        house = AiringRoom.new(steps: { STEP => -1.0 })
        events = detector.events(at(STEP, house))
        assert(events.all? { it.direction == :fall && it.z.negative? })
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

    private

    def detector
        Sensorium::Transient::Detector.new(SETUP, profiles: @profiles)
    end

    def profile(device) = @profiles.find { it.device == device }

    def at(index, house = @house)
        Sensorium::Snapshot.from(house, SETUP, at: house.time(index))
    end

    # z as the readings make it: s's change over the window, less the
    # median, over σ.
    def expected(window)
        value = ->(index) { @house.readings_at(index).last.value }
        scale = profile("s").own[window]
        change = value[STEP] - value[STEP - (window / 600)]
        (change - scale.median) / scale.sigma
    end
end
