# frozen_string_literal: true

require "json"
require "time"
require "zlib"

# A room recorded from a real house, as a source: thirty winter days of
# its sensors' raw readings, the outside's, and its heating and aircon
# events, its devices renamed. The recording lives out of git, in
# local/fixture/room.json.gz (local/make_fixture.rb writes it); without
# it, RecordedRoom.load is nil.
class RecordedRoom
    PATH = File.expand_path("../../local/fixture/room.json.gz", __dir__)
    ROOM = "room"

    def self.load
        return unless File.exist?(PATH)
        new(JSON.parse(Zlib::GzipReader.open(PATH, &:read)))
    end

    attr_reader :from, :to

    def initialize(data)
        @from, @to = data.values_at("from", "to").map { Time.iso8601(it) }
        @sensors = data["sensors"]
        @readings = data["readings"].transform_values { read(it) }
        @externals = data["externals"].transform_values { outside(it) }
        @events = data["events"].transform_values { timed(it) }
    end

    def sensors(_quantity)
        @sensors.map do |sensor|
            Sensorium::Sensor.new(name: sensor["name"], location: ROOM,
                                  tags: sensor["tags"])
        end
    end

    def readings(quantity, from, to, devices = nil)
        @readings.fetch(quantity).select do |reading|
            (from..to).cover?(reading.time) &&
                (devices.nil? || devices.include?(reading.device))
        end
    end

    def externals(quantity, from, to)
        @externals.fetch(quantity).select { (from..to).cover?(it.time) }
    end

    def events(name, from, to)
        @events.fetch(name, []).select { (from..to).cover?(it.first) }
    end

    private

    def read(rows)
        rows.map do |time, device, value, temperature|
            Sensorium::Reading.new(time: Time.iso8601(time), location: ROOM,
                                   device:, value:,
                                   context: { temperature: })
        end
    end

    def outside(rows)
        rows.map do |time, value, temperature|
            Sensorium::Reading.new(time: Time.iso8601(time), location: nil,
                                   device: "outside", value:,
                                   context: { temperature: })
        end
    end

    def timed(rows)
        rows.map { |time, value| [Time.iso8601(time), ROOM, value] }
    end
end
