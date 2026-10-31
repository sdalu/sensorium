# frozen_string_literal: true

require "support/fake_house"

# FakeHouse's ten January days learned once, for the stores' tests.
module Winter
    def self.learned
        @learned ||= Sensorium::Learner.new(
            FakeHouse.new, Sensorium::Presets.room,
            from: FakeHouse::START, to: FakeHouse::START + (10 * 86_400)
        ).learn
    end
end
