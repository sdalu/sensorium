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

    # No ceiling or floor sensor measures humidity: a wall unit is its
    # reference, else a radiator valve. Temperature takes them too, but
    # only where neither a ceiling nor a floor is.
    def test_humidity_has_places_of_its_own
        sensors = [sensor("ceil", "a", "ceiling"), sensor("tado", "a", "valve"),
                   sensor("airzone", "a", "wall"), sensor("tado", "b", "valve")]
        found = Sensorium::Learner::References.new(
            sensors.drop(1), {}, Sensorium::Presets.room(Sensorium::Presets::HUMIDITY)
        ).all
        assert_equal({ "a" => %w[airzone], "b" => %w[tado] }, found)
        temperature = Sensorium::Learner::References.new(
            sensors, {}, Sensorium::Presets.room
        ).all
        assert_equal({ "a" => %w[ceil], "b" => %w[tado] }, temperature)
    end

    # What the source listed, and the references set: what a store keeps
    # offsets for.
    def test_a_learning_says_what_was_listed
        learned = learn("blue" => %w[x])
        assert_includes learned.sensors, %w[room-a airzone]
        assert_includes learned.sensors, %w[blue x]
        refute_includes learned.sensors, %w[room-a nobody]
    end

    # A reference set by hand is read, though no sensor lists it.
    def test_a_reference_set_is_read
        house = FakeHouse.new
        locations = { "blue" => Sensorium::Location.new(name: "blue",
                                                        references: %w[x]) }
        Sensorium::Learner.new(house, Sensorium::Presets.room,
                               from: FakeHouse::START,
                               to: FakeHouse::START + 86_400, locations:).learn
        assert_includes house.queried, "x"
    end

    private

    def sensor(name, location, *tags)
        Sensorium::Sensor.new(name:, location:, tags:)
    end

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
