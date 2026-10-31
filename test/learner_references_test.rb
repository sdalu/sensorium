# frozen_string_literal: true

require "test_helper"
require "support/fake_house"

# Learner with the locations' references set (FakeHouse).
class LearnerReferencesTest < Minitest::Test
    # A plain sensor, once set, makes the blue room learnable.
    def test_a_set_reference_can_be_any_sensor
        found = sole(learn("blue" => %w[plain-blue]), "blue", "tado")
        assert_equal "plain-blue", found.reference
        assert_in_delta(-0.5, found.constant, 0.05)
        assert_nil found.neighbour
    end

    # Their mean is the reference; each of them is learned against it.
    def test_several_references_are_learned_against_their_mean
        learned = learn("room-a" => %w[ceil-a plain-a])
        ceiling, plain, tado = %w[ceil-a plain-a tado].map do |device|
            sole(learned, "room-a", device)
        end
        assert_equal "ceil-a+plain-a", tado.reference
        assert_in_delta(-0.2, ceiling.constant, 0.05)
        assert_in_delta 0.2, plain.constant, 0.05
        assert_in_delta(-1.1, tado.constant, 0.05)
        assert_nil ceiling.neighbour
    end

    private

    # Learned with those locations' references set.
    def learn(references)
        locations = references.to_h do |name, devices|
            [name, Sensorium::Location.new(name:, references: devices)]
        end
        start = FakeHouse::START
        Sensorium::Learner.new(FakeHouse.new, Sensorium::Presets.room,
                               from: start,
                               to: start + (FakeHouse::DAYS * 86_400),
                               locations:).learn
    end

    # The one offset learned of a location's device.
    def sole(learned, location, device)
        found = learned.offsets.select do |offset|
            offset.location == location && offset.device == device
        end
        assert_equal 1, found.size
        found.first
    end
end
