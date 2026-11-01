# frozen_string_literal: true

# A made-up room, thirty days of a reading every bin: the truth a daily
# wave of ±2 around 20 with a slow wander, each device reading it with
# its bias and a normal noise of its own (noise: { device => [bias,
# σ] }), independent; the first device is tagged ceiling. heated: the
# radiators on six hours in twelve (a valve opening every bin
# meanwhile), "wall" reading 1.0 higher while they are, and an hour
# after.
class NoisyRoom
    START = Time.utc(2026, 1, 5)
    STEP  = 600
    SIZE  = 30 * 144

    def initialize(noise, heated: false)
        @devices = noise.keys
        @random = Random.new(5)
        @valves = (0...SIZE).select { heated && it % 72 < 36 }
        @hot = @valves.flat_map { |index| (index..(index + 6)).to_a }
                      .to_set
        @readings = build(noise)
    end

    def events(name, from, to)
        return [] unless name == "heating"
        @valves.map { [START + (it * STEP), "room", 1] }
               .select { (from..to).cover?(it.first) }
    end

    def sensors(_quantity)
        @devices.each_with_index.map do |name, index|
            Sensorium::Sensor.new(name:, location: "room",
                                  tags: index.zero? ? %w[ceiling] : [])
        end
    end

    def readings(_quantity, from, to, _devices)
        @readings.select { (from..to).cover?(it.time) }
    end

    private

    def build(noise)
        (0...SIZE).flat_map do |index|
            noise.map do |device, (bias, sigma)|
                reading(index, device,
                        value(index, bias + heat(device, index), sigma))
            end
        end
    end

    def heat(device, index)
        device == "wall" && @hot.include?(index) ? 1.0 : 0.0
    end

    def value(index, bias, sigma)
        truth(index) + bias + (sigma * normal)
    end

    def truth(index)
        20 + (2 * Math.sin(index * 2 * Math::PI / 144)) +
            Math.sin(index / 500.0)
    end

    def normal
        Math.sqrt(-2 * Math.log(1 - @random.rand)) *
            Math.cos(2 * Math::PI * @random.rand)
    end

    def reading(index, device, value)
        Sensorium::Reading.new(time: START + (index * STEP),
                               location: "room", device:, value:)
    end
end
