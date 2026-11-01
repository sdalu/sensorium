# frozen_string_literal: true

require "test_helper"
require "support/fake_house"

# A History is its span: a span given beside it would be ignored, so
# each of the four learners refuses it.
class HistorySpanTest < Minitest::Test
    SETUP  = Sensorium::Presets.room
    WINDOW = { from: FakeHouse::START,
               to: FakeHouse::START + (FakeHouse::DAYS * 86_400) }.freeze

    def setup
        @history = Sensorium::History.load(FakeHouse.new, SETUP, **WINDOW)
    end

    def test_the_learner_refuses_a_span_beside_a_history
        assert_raises(ArgumentError) do
            Sensorium::Learner.new(FakeHouse.new, SETUP, history: @history,
                                                         **WINDOW)
        end
    end

    def test_dynamics_and_transients_refuse_it
        [Sensorium::Dynamics, Sensorium::Transient].each do |learner|
            assert_raises(ArgumentError) do
                learner.learn(FakeHouse.new, SETUP, history: @history,
                                                    **WINDOW)
            end
        end
    end

    def test_collocation_refuses_it
        assert_raises(ArgumentError) do
            Sensorium::Collocation.learn(FakeHouse.new, SETUP,
                                         offsets: [], history: @history,
                                         **WINDOW)
        end
    end
    end
end
