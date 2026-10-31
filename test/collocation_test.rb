# frozen_string_literal: true

require "test_helper"

# Triple collocation: each series' error variance from the others,
# without the truth. A made-up room, thirty days of a reading every
# bin: the truth a daily wave of ±2 around 20 with a slow wander; the
# ceiling reads it with a normal noise of σ 0.1, "wall" 0.5 above it
# with σ 0.2, "door" 0.3 below with σ 0.3, each independent.
class CollocationTest < Minitest::Test
    START = Time.utc(2026, 1, 5)
    STEP  = 600
    SIZE  = 30 * 144
    NOISE = { "ceil" => [0.0, 0.1], "wall" => [0.5, 0.2],
              "door" => [-0.3, 0.3] }.freeze

    # A source of the room above; heated: the radiators on six hours in
    # twelve (a valve opening every bin meanwhile), "wall" reading 1.0
    # higher while they are, and an hour after.
    class Room
        def initialize(noise, heated: false)
            @random = Random.new(5)
            @valves = (0...SIZE).select { heated && it % 72 < 36 }
            @hot = @valves.flat_map { |index| (index..(index + 6)).to_a }
                          .to_set
            @readings = (0...SIZE).flat_map do |index|
                noise.map do |device, (bias, sigma)|
                    reading(index, device,
                            value(index, bias + heat(device, index), sigma))
                end
            end
        end

        def events(name, from, to)
            return [] unless name == "heating"
            @valves.map { [START + (it * STEP), "room", 1] }
                   .select { (from..to).cover?(it.first) }
        end

        def sensors(_quantity)
            [Sensorium::Sensor.new(name: "ceil", location: "room",
                                   tags: %w[ceiling]),
             Sensorium::Sensor.new(name: "wall", location: "room"),
             Sensorium::Sensor.new(name: "door", location: "room")]
        end

        def readings(_quantity, from, to, _devices)
            @readings.select { (from..to).cover?(it.time) }
        end

        private

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

    def test_the_noises_are_recovered
        found = learn(Room.new(NOISE)).first
        NOISE.each do |device, (_, sigma)|
            assert_in_delta sigma, found.sigma(device), 0.15 * sigma
        end
    end

    # Each sensor corrected with what held at each bin: wall's heating
    # term taken out, its noise is its own again.
    def test_a_sensor_is_corrected_with_its_terms
        found = learn(Room.new(NOISE, heated: true)).first
        NOISE.each do |device, (_, sigma)|
            assert_in_delta sigma, found.sigma(device), 0.15 * sigma
        end
    end

    def test_what_it_was_learned_on
        found = learn(Room.new(NOISE))
        assert_equal 1, found.size
        assert_equal %w[room temperature winter],
                     found.first.to_h.values_at(:location, :quantity, :regime)
        assert_operator found.first.samples, :>=, SIZE - 10
    end

    # Two series are not enough to tell the errors apart.
    def test_three_series_at_least
        two = NOISE.except("door")
        assert_empty learn(Room.new(two))
    end

    # x0 = t, x1 = t + e, x2 = t - e: x0's estimate is -var(e), x1's
    # cov(e, 2e) = 2 var(e).
    def test_a_negative_variance_is_not_measurable
        random = Random.new(3)
        e = Array.new(1000) { random.rand - 0.5 }
        t = Array.new(1000) { Math.sin(it / 10.0) }
        found = Sensorium::Collocation.sigmas(
            { "a" => t, "b" => t.zip(e).map(&:sum), "c" => apart(t, e) }
        )
        assert_nil found["a"]
        assert_in_delta 0.408, found["b"], 0.02
    end

    # References set to ceil and wall: their mean is no series of its
    # own beside them, each is collocated as corrected to it.
    def test_several_references_are_collocated_one_by_one
        locations = { "room" => Sensorium::Location.new(
            name: "room", references: %w[ceil wall]
        ) }
        found = learn(Room.new(NOISE), locations:)
        NOISE.each do |device, (_, sigma)|
            assert_in_delta sigma, found.first.sigma(device).to_f,
                            0.15 * sigma, device
        end
        refute found.first.sigmas.key?("ceil+wall")
    end

    private

    def apart(xs, ys) = xs.zip(ys).map { |x, y| x - y }

    def learn(room, locations: {})
        setup = Sensorium::Presets.room
        span = { from: START, to: START + (SIZE * STEP) }
        offsets = Sensorium::Learner.new(room, setup, **span, locations:)
                                    .learn.offsets
        Sensorium::Collocation.learn(room, setup, **span, offsets:,
                                                          locations:)
    end
end
