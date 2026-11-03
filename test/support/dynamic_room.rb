# frozen_string_literal: true

# A made-up room for Dynamics' tests, a reading every bin (600 s), from
# start, answering as a source does. Per hour,
#   dr/dt = a × (outside - r) + 0.5 × heating + noise
# (per bin, a / 6 and 0.5 / 6), the outside a daily wave of ±5 around
# 5, the radiators on three hours in six. noise: :white, uniform over
# ±0.05 per bin; :ar1, an AR(1) of coefficient 0.9 (each bin's noise
# 0.9 of the last's plus uniform ±0.02). constant: the room is 20 plus
# uniform ±2 every bin, whatever else happens. aircon: on two hours a
# day, cooling the room by 0.3 a bin meanwhile.
class DynamicRoom
    STEP    = 600
    HEATING = Sensorium::Influence::Switch.new(name: "heating", hold: 0)
    AIRCON  = Sensorium::Influence::Mode.new(name: "aircon", hold: 0)

    attr_reader :size, :rows

    # kind: noise:, constant:, aircon:, as above.
    def initialize(start, size, a: 0.1, **kind)
        @start  = start
        @size   = size
        @random = Random.new(7)
        @a      = a / 6.0
        @kind   = { noise: :white, constant: false, aircon: false, **kind }
        build
    end

    def sensors(_quantity)
        [Sensorium::Sensor.new(name: "ceil", location: "room",
                               tags: %w[ceiling])]
    end

    def readings(_quantity, from, to, _devices) = within(@readings, from, to)
    def externals(_quantity, from, to) = within(@outside, from, to)

    def events(name, from, to)
        list = name == "aircon" ? @aircon : @heating
        list.select { (from..to).cover?(it.first) }
    end

    # The value 1 hour (six bins) after each bin, as a Model predicts it
    # with the room's true terms, less what it was.
    def hour_errors
        @rows.each_cons(7).map do |first, *, last|
            change = (@a * (last[:outside] - first[:r])) +
                     (last[:on] ? 0.5 / 6 : 0)
            last[:r] - (first[:r] + (6 * change))
        end
    end

    private

    def within(list, from, to) = list.select { (from..to).cover?(it.time) }

    def build
        @readings = []
        @outside  = []
        @heating  = []
        @aircon   = []
        @rows     = []
        r = 18.0
        @w = 0.0
        @size.times { |i| r = step(i, r) }
    end

    def step(index, r)
        row = row(index, r)
        record(@start + (index * STEP), row)
        return constant if @kind[:constant]
        r + (@a * (row[:outside] - r)) + forced(row) + noise
    end

    def constant = 20 + ((@random.rand - 0.5) * 4)

    # The radiators' warming and the aircon's cooling, per bin.
    def forced(row) = (row[:on] ? 0.5 / 6 : 0) + (row[:cool] ? -0.3 : 0)

    def row(index, r)
        { r:, outside: 5 + (5 * Math.sin(index * 2 * Math::PI / 144)),
          on: index % 36 < 18, cool: @kind[:aircon] && index % 144 < 12 }
    end

    def record(time, row)
        @rows << row
        @readings << reading(time, "room", "ceil", row[:r])
        @outside << reading(time, nil, "outside", row[:outside])
        @heating << [time, nil, 1] if row[:on]
        @aircon << [time, "room", "cooling"] if row[:cool]
    end

    def noise
        return (@random.rand - 0.5) * 0.1 if @kind[:noise] == :white
        @w = (0.9 * @w) + ((@random.rand - 0.5) * 0.04)
    end

    def reading(time, location, device, value)
        Sensorium::Reading.new(time:, location:, device:, value:)
    end
end
