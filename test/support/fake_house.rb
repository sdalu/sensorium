# frozen_string_literal: true

# A constructed house, ten days of it, answering as a source does, set
# up by Sensorium::Presets.room. Every value is made up:
#   room-a  ceiling "ceil-a"; "plain-a", untagged, 0.4 above it;
#           tado reads 0.9 below it; airzone 1.1 above,
#           1.6 above while the radiators' water is hot; its aircon ran
#           30 hours, cooling, airzone reading 5 °C meanwhile
#   room-b  floor "leak-b" (its reference); airzone 0.4 above, less 0.3 ×
#           (leak-b - the garage): the garage door is near it
#   garage  "g1", untagged: a neighbour, never a reference
#   blue    "plain-blue", untagged, and tado 0.5 below it: no reference
#           unless one is set
#   few     ceiling "ceil-f"; tado seen only 20 times: too few
# tado and airzone are the heaters' own sensors: no neighbours.
class FakeHouse
    START = Time.utc(2026, 1, 5)
    DAYS  = 10
    STEP  = 600
    HOT   = 3600

    attr_reader :queried

    # start: the first reading's time.
    def initialize(start: START)
        @start = start
        @random = Random.new(42)
        @readings = []
        @valves = []
        build
    end

    def sensors(_quantity)
        [sensor("ceil-a", "room-a", "ceiling"), sensor("plain-a", "room-a"),
         heater("tado", "room-a"), heater("airzone", "room-a"),
         sensor("plain-blue", "blue"), heater("tado", "blue"),
         sensor("leak-b", "room-b", "floor"), heater("airzone", "room-b"),
         sensor("g1", "garage"),
         sensor("ceil-f", "few", "ceiling"), heater("tado", "few")]
    end

    def readings(_quantity, from, to, devices = nil)
        @queried = devices
        @readings.select do |reading|
            (from..to).cover?(reading.time) &&
                (devices.nil? || devices.include?(reading.device))
        end
    end

    def events(name, from, to)
        case name
        when "heating" then @valves.select { (from..to).cover?(it.first) }
        when "aircon"
            aircon_times.grep(from..to).map { [it, "room-a", "cooling"] }
        else []
        end
    end

    # The bins the learner counts as hot, by its own rule.
    def hot
        open = @valves.select { it.last.positive? }.map(&:first)
        Sensorium::Series.new(STEP).spans(open, HOT)
    end

    private

    def sensor(name, location, *tags)
        Sensorium::Sensor.new(name:, location:, tags:)
    end

    def heater(name, location)
        Sensorium::Sensor.new(name:, location:, neighbour: false)
    end

    def build
        times = (0...(DAYS * 144)).map { @start + (it * STEP) }
        times.each_slice(2) { |pair| valve(pair.first) }
        hot = self.hot
        times.each { tick(it, hot.include?(bin(it))) }
        times.first(20).each { add(it, "few", "tado", 19.0) }
    end

    def bin(time) = time.to_i / STEP * STEP

    # Valves open every other three hours.
    def valve(time) = @valves << [time, "room-a", time.hour % 6 < 3 ? 40 : 0]

    def tick(time, hot)
        room_a(time, hot)
        add(time, "few", "ceil-f", 18 + Math.cos(time.to_i / 25_000.0))
        blue(time)
        room_b(time)
    end

    def room_a(time, hot)
        a = 20 + Math.sin(time.to_i / 20_000.0)
        add(time, "room-a", "ceil-a", a)
        add(time, "room-a", "plain-a", a + 0.4 + noise)
        add(time, "room-a", "tado", a - 0.9 + noise)
        add(time, "room-a", "airzone", a + airzone_a(time, hot))
    end

    def blue(time)
        blue = 21 + Math.sin(time.to_i / 15_000.0)
        add(time, "blue", "plain-blue", blue)
        add(time, "blue", "tado", blue - 0.5 + noise)
    end

    def room_b(time)
        garage = 10 + (5 * Math.sin(time.to_i / 50_000.0))
        b = 19 + Math.cos(time.to_i / 30_000.0)
        add(time, "garage", "g1", garage)
        add(time, "room-b", "leak-b", b)
        add(time, "room-b", "airzone", b + airzone_b(b, garage))
    end

    def airzone_b(room, garage) = 0.4 - (0.3 * (room - garage)) + noise

    def airzone_a(time, hot)
        return 5.0 if aircon_times.include?(time)
        (hot ? 1.6 : 1.1) + noise
    end

    def aircon_times
        @aircon_times ||= (0...180).map { @start + (2 * 86_400) + (it * STEP) }
    end

    def noise = (@random.rand - 0.5) * 0.2

    def add(time, location, device, value)
        @readings << Sensorium::Reading.new(time:, location:, device:, value:)
    end
end
