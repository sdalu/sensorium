# frozen_string_literal: true

# A made-up sensor "s" in "room", with no reference, a reading every
# bin (600 s) from START, its values given, answering as a source does.
class OneSensor
    START = Time.utc(2026, 1, 5)
    STEP  = 600

    def initialize(values)
        @all = values.each_with_index.map do |value, index|
            Sensorium::Reading.new(time: time(index), location: "room",
                                   device: "s", value:)
        end
    end

    def sensors(_quantity)
        [Sensorium::Sensor.new(name: "s", location: "room")]
    end

    def readings(_quantity, from, to, _devices = nil)
        @all.select { (from..to).cover?(it.time) }
    end

    def size = @all.size
    def time(index) = START + (index * STEP)
    def last = time(size - 1)

    # The snapshot at the index-th reading, its hour before as history.
    def snapshot(index)
        latest = @all[index]
        history = @all[[index - 6, 0].max..index]
        Sensorium::Snapshot.new(at: latest.time,
                                latest: { %w[room s] => latest },
                                history: { %w[room s] => history })
    end
end
