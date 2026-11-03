# frozen_string_literal: true

require "support/winter"

# What is known of FakeHouse's temperature after its ten days, as a
# store gives it: Winter's offsets and shifts, the transient profiles of
# the same days, a still room's dynamics for room-a and room-b, and
# tado's track in room-a drifting by 0.3 °C, last updated ten minutes
# before its third day.
module HouseKnowledge
    SETUP   = Sensorium::Presets.room
    TRACKED = (2 * 86_400) - 600
    SPAN    = { from: FakeHouse::START,
                to: FakeHouse::START + (10 * 86_400) }.freeze

    def self.knowledge
        @knowledge ||= Sensorium::Knowledge.new(
            offsets: Winter.learned.offsets, shifts: Winter.learned.shifts,
            locations: { "room-b" => Sensorium::Location.new(name: "room-b",
                                                             max_age: 30) },
            tracks:, dynamics: %w[room-a room-b].map { model(it) },
            transients: Sensorium::Transient.learn(FakeHouse.new, SETUP,
                                                   **SPAN)
        )
    end

    def self.model(location)
        Sensorium::Dynamics::Model.new(
            location:, quantity: "temperature", regime: "winter", a: 0.0,
            b: {}, c: 0.0, q: 0.01, bin: 600, steps: 1000
        )
    end

    def self.tracks
        tado = Winter.learned.offsets.find do |offset|
            offset.location == "room-a" && offset.device == "tado"
        end
        track = Sensorium::Track.fresh(tado, 0.0025)
                                .with(delta: 0.3, state: :drifting,
                                      at: FakeHouse::START + TRACKED)
        { %w[room-a tado] => track }
    end
end
