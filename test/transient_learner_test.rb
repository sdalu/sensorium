# frozen_string_literal: true

require "test_helper"
require "support/airing_room"

# The Learner with Influence::Transient: the bins where a sensor moves
# apart from its reference, and its hold after, are left out of its
# offset. AiringRoom's s reads 0.5 above ceil, and 2 below that for 50
# minutes every 160 (an airing by s alone): each airing's fall and
# rise, and their 30 minutes' hold, cover it. Airings this frequent are
# one change in 16: a rate of 12 a day (one in 12) leaves them beyond
# the thresholds, and some noise with them, hence min_samples 200.
class TransientLearnerTest < Minitest::Test
    START   = AiringRoom::START
    SPAN    = AiringRoom::DAYS * 86_400
    AIRINGS = [16, 5].freeze

    # 5 bins low in 16 drag the median of the rest toward them.
    def test_without_it_an_airing_moves_the_constant
        constant = offset([]).constant
        assert_operator 0.5 - constant, :>, 0.02
    end

    def test_with_it_the_airings_are_left_out
        offset = offset([Sensorium::Influence::Transient.new])
        assert_in_delta 0.5, offset.constant, 0.005
        assert_operator offset.p10, :>, -0.2
    end

    # Each airing's two edges, their hold after: no Shift of its own.
    def test_a_transient_has_no_shift
        learned = learn([Sensorium::Influence::Transient.new])
        assert_empty learned.shifts
    end

    def test_the_influence
        transient = Sensorium::Influence::Transient.new
        assert_equal ["transient", 1800], [transient.name, transient.hold]
        setup = Sensorium::Setup.new(quantity: Sensorium::Presets::TEMPERATURE,
                                     influences: [transient])
        assert_equal [transient], setup.transients
        assert_equal [[600, 1200], 0.2],
                     setup.to_h.values_at(:transient_windows, :transient_rate)
    end

    def test_the_room_preset_leaves_it_out
        [Sensorium::Presets::TEMPERATURE,
         Sensorium::Presets::HUMIDITY].each do |quantity|
            assert_empty Sensorium::Presets.room(quantity).transients
        end
    end

    private

    def learn(influences)
        setup = Sensorium::Setup.new(quantity: Sensorium::Presets::TEMPERATURE,
                                     places: %w[ceiling], influences:,
                                     rate: false, gain: false,
                                     transient_rate: 12, min_samples: 200)
        Sensorium::Learner.new(AiringRoom.new(airings: AIRINGS), setup,
                               from: START, to: START + SPAN).learn
    end

    def offset(influences)
        learn(influences).offsets.find { it.device == "s" }
    end
end
