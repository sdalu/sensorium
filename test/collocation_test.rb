# frozen_string_literal: true

require "test_helper"
require "support/noisy_room"

# Triple collocation: each series' error variance from the others,
# without the truth. A made-up room, thirty days of a reading every
# bin: the truth a daily wave of ±2 around 20 with a slow wander; the
# ceiling reads it with a normal noise of σ 0.1, "wall" 0.5 above it
# with σ 0.2, "door" 0.3 below with σ 0.3, each independent.
class CollocationTest < Minitest::Test
    START = NoisyRoom::START
    STEP  = NoisyRoom::STEP
    SIZE  = NoisyRoom::SIZE
    NOISE = { "ceil" => [0.0, 0.1], "wall" => [0.5, 0.2],
              "door" => [-0.3, 0.3] }.freeze

    def test_the_noises_are_recovered
        found = learn(NoisyRoom.new(NOISE)).first
        NOISE.each do |device, (_, sigma)|
            assert_in_delta sigma, found.sigma(device), 0.15 * sigma
        end
    end

    # Each sensor corrected with what held at each bin: wall's heating
    # term taken out, its noise is its own again.
    def test_a_sensor_is_corrected_with_its_terms
        found = learn(NoisyRoom.new(NOISE, heated: true)).first
        NOISE.each do |device, (_, sigma)|
            assert_in_delta sigma, found.sigma(device), 0.15 * sigma
        end
    end

    def test_what_it_was_learned_on
        found = learn(NoisyRoom.new(NOISE))
        assert_equal 1, found.size
        assert_equal %w[room temperature winter],
                     found.first.to_h.values_at(:location, :quantity, :regime)
        assert_operator found.first.samples, :>=, SIZE - 10
    end

    # Two series are not enough to tell the errors apart.
    def test_three_series_at_least
        two = NOISE.except("door")
        assert_empty learn(NoisyRoom.new(two))
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
        found = learn(NoisyRoom.new(NOISE), locations:)
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
