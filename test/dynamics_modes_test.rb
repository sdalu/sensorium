# frozen_string_literal: true

require "test_helper"

# Dynamics on a room whose reference holds 20, but 15 while its aircon
# (a Mode) holds: the step into the Mode's first bin would take in its
# onset, and a forecast across the Mode its cooling; neither counts.
# The model is the calm room's, c 0, and nothing errs.
class DynamicsModesTest < Minitest::Test
    START  = Time.utc(2026, 1, 5)
    BIN    = 3600
    HOURS  = 400
    AIRCON = Sensorium::Influence::Mode.new(name: "aircon", hold: 0)
    # The hours the aircon holds: six from 100, 200 and 300.
    COOLED = [100, 200, 300].flat_map { |h| (h...(h + 6)).to_a }.freeze

    # The room, hourly, as a source.
    class Room
        def sensors(_quantity)
            [Sensorium::Sensor.new(name: "ceil", location: "room",
                                   tags: %w[ceiling])]
        end

        def readings(_quantity, from, to, _devices = nil)
            (0...HOURS).filter_map do |hour|
                time = START + (hour * BIN)
                next unless (from..to).cover?(time)
                value = COOLED.include?(hour) ? 15.0 : 20.0
                Sensorium::Reading.new(time:, location: "room", device: "ceil",
                                       value:)
            end
        end

        def externals(_quantity, _from, _to) = []

        def events(name, from, to)
            return [] unless name == "aircon"
            COOLED.map { [START + (it * BIN), "room", "cooling"] }
                  .select { (from..to).cover?(it.first) }
        end
    end

    def test_a_modes_onset_is_in_no_step_and_no_forecast
        model = Sensorium::Dynamics.learn(Room.new, room,
                                          from: START,
                                          to: START + (HOURS * BIN)).first
        refute_nil model
        assert_in_delta 0.0, model.c, 1e-9
        assert_in_delta 0.0, model.q, 1e-9
        assert_in_delta 0.0, model.rms_model, 1e-9
    end

    private

    def room
        Sensorium::Setup.new(quantity: Sensorium::Presets::TEMPERATURE,
                             places: %w[ceiling], bin: BIN, min_samples: 10,
                             influences: [AIRCON])
    end
end
