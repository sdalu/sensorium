# frozen_string_literal: true

require "test_helper"
require "support/dynamic_room"

# Priors on a location's dynamics: what the caller knows of a room
# (its time constant from its walls, say), pulling a fit where data is
# thin and giving way where it is plentiful.
class DynamicsPriorTest < Minitest::Test
    START = Time.utc(2026, 1, 5)
    A     = 0.1 / 6
    Prior = Sensorium::Dynamics::Prior

    def test_no_prior_learns_as_without
        assert_equal learn(room), learn(room, priors: {})
    end

    # A prior far wider than what the data says moves nothing.
    def test_a_loose_prior_gives_way_to_the_data
        free = learn(room).first.a
        loose = learn(room, priors: { "room" => Prior.new(a: [0.5, 1e3]) })
        assert_in_delta free, loose.first.a, 1e-9
    end

    def test_a_tight_prior_holds
        tight = { "room" => Prior.new(a: [0.02, 1e-7]) }
        assert_in_delta 0.02, learn(room, priors: tight).first.a, 1e-5
    end

    def test_priors_may_be_asked_for_by_location_and_regime
        asked = []
        priors = lambda do |location, regime|
            asked << [location, regime]
            Prior.new(a: [0.02, 1e-7])
        end
        model = learn(room, priors:).first
        assert_includes asked, %w[room all]
        assert_in_delta 0.02, model.a, 1e-5
    end

    # Two hundred noisy steps: the right prior lands nearer the truth
    # than the data alone.
    def test_a_prior_helps_where_data_is_thin
        steps = thin_steps
        free = Sensorium::Dynamics::Regression.fit(steps)
        prior = Prior.new(a: [A, A / 4])
        held = Sensorium::Dynamics::Regression.fit(steps, prior)
        assert_operator (held[:a] - A).abs, :<, (free[:a] - A).abs
    end

    private

    def room(**) = DynamicRoom.new(START, 30 * 144, **)

    def learn(room, priors: nil)
        setup = Sensorium::Setup.new(quantity: Sensorium::Presets::TEMPERATURE,
                                     places: %w[ceiling], outside: "outside",
                                     influences: [DynamicRoom::HEATING])
        Sensorium::Dynamics.learn(room, setup, from: START,
                                               to: START + (room.size * 600),
                                               priors:)
    end

    def thin_steps
        random = Random.new(11)
        (0...200).map { step(it, (random.rand - 0.5) * 0.4) }
    end

    def step(index, noise)
        gap = -10.0 + (3 * Math.sin(index / 20.0))
        on = index % 3 < 1 ? ["heating"] : []
        change = (A * gap) + (on.empty? ? 0 : 0.08) + noise
        Sensorium::Dynamics::History::Step.new(bin: index * 600, gap:, on:,
                                               change:)
    end
end
