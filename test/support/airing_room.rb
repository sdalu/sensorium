# frozen_string_literal: true

# A made-up room for the transient detector's tests, ten days of a
# reading every bin (600 s) from START, answering as a source does:
# "ceil" (on the ceiling, the reference) reads 20, "s" reads 0.5 above
# it, each with its own noise, uniform over ±0.05. Options:
#   steps:   { bin index => change }, s moving by that much for good
#   airings: [every, lasting], s reading 2 below its usual from each
#            multiple of `every` bins, for `lasting` bins
#   wave:    the amplitude of a daily wave both read (the whole room)
#   swings:  [every, lasting], the aircon running ("cooling") from each
#            multiple of `every` bins for `lasting` bins, s jumping by
#            ±1 from one bin to the next meanwhile
class AiringRoom
    START = Time.utc(2026, 1, 5)
    DAYS  = 10
    STEP  = 600
    SIZE  = DAYS * 86_400 / STEP

    def initialize(steps: {}, airings: nil, wave: 0.0, swings: nil)
        @random = Random.new(11)
        @kind   = { steps:, airings:, wave:, swings: }
        @readings = []
        @aircon = []
        SIZE.times { record(it) }
    end

    def sensors(_quantity)
        [Sensorium::Sensor.new(name: "ceil", location: "room",
                               tags: %w[ceiling]),
         Sensorium::Sensor.new(name: "s", location: "room")]
    end

    def readings_at(index) = @readings.select { it.time == time(index) }

    def readings(_quantity, from, to, devices = nil)
        @readings.select do |reading|
            (from..to).cover?(reading.time) &&
                (devices.nil? || devices.include?(reading.device))
        end
    end

    def events(name, from, to)
        return [] unless name == "aircon"
        @aircon.select { (from..to).cover?(it.first) }
    end

    def time(index) = START + (index * STEP)

    private

    def record(index)
        room = 20 + wave(index)
        @readings << reading(index, "ceil", room + noise)
        @readings << reading(index, "s", room + 0.5 + moved(index) + noise)
        @aircon << [time(index), "room", "cooling"] if swinging?(index)
    end

    def moved(index)
        @kind[:steps].sum { |at, change| at <= index ? change : 0.0 } +
            (aired?(index) ? -2.0 : 0.0) + swing(index)
    end

    def wave(index)
        @kind[:wave] * Math.sin(index * 2 * Math::PI / 144)
    end

    def aired?(index) = within?(@kind[:airings], index)
    def swinging?(index) = within?(@kind[:swings], index)

    def swing(index)
        return 0.0 unless swinging?(index)
        index.even? ? 1.0 : -1.0
    end

    def within?(pattern, index)
        return false unless pattern
        every, lasting = pattern
        index % every < lasting
    end

    def noise = (@random.rand - 0.5) * 0.1

    def reading(index, device, value)
        Sensorium::Reading.new(time: time(index), location: "room", device:,
                               value:)
    end
end
