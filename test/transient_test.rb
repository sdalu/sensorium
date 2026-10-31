# frozen_string_literal: true

require "test_helper"
require "support/airing_room"

# Transient.learn: each sensor's robust scales of its changes over each
# window, its own and against its reference, in AiringRoom.
class TransientTest < Minitest::Test
    START = AiringRoom::START
    SPAN  = AiringRoom::DAYS * 86_400

    # Uniform noise of ±0.05 on each reading: a change is the
    # difference of two, triangular over ±0.1, whose |median| is
    # 0.1 × (1 - 1/√2), σ 1.4826 times that.
    TRIANGULAR = 1.4826 * 0.1 * (1 - Math.sqrt(0.5))

    def test_a_sensors_own_scale_is_its_changes_spread
        own = profile.own
        assert_equal [600, 1200], own.keys
        own.each_value do |scale|
            assert_in_delta TRIANGULAR, scale.sigma, 0.1 * TRIANGULAR
            assert_in_delta 0.0, scale.median, 0.005
        end
    end

    # s - ceil holds both noises: its change is the sum of four, near
    # normal with σ √(4 × 0.1² / 12).
    def test_the_relative_scale_holds_the_references_noise_too
        sigma = Math.sqrt(4 * 0.01 / 12)
        profile.relative.each_value do |scale|
            assert_in_delta sigma, scale.sigma, 0.1 * sigma
        end
    end

    def test_a_reference_has_no_relative_scale
        ceil = profile("ceil")
        refute_empty ceil.own
        assert_empty ceil.relative
    end

    def test_a_profile_says_what_it_is_of
        assert_equal %w[room s temperature all],
                     profile.to_h.values_at(:location, :device, :quantity,
                                            :regime)
    end

    # The whole room moving widens the own scale; against the
    # reference, s is as calm as ever.
    def test_a_room_wide_change_widens_only_the_own_scale
        found = sigmas(profile(house: AiringRoom.new(wave: 3.0)))
        calm = sigmas(profile)
        assert_operator found.first, :>, 2 * calm.first
        assert_in_delta calm.last, found.last, 0.1 * calm.last
    end

    def test_too_few_changes_give_no_profile
        assert_empty learn(setup(min_samples: 5000))
    end

    # 1440 readings carried an hour past the last: 1446 bins, 1445
    # changes over ten minutes, 1444 over twenty.
    def test_a_window_with_too_few_changes_is_left_out
        found = learn(setup(min_samples: 1445)).find { it.device == "s" }
        assert_equal [600], found.own.keys
    end

    # The aircon's swings of ±1 every bin are left out, with their hold.
    def test_the_bins_under_a_mode_are_left_out
        aircon = Sensorium::Influence::Mode.new(name: "aircon")
        found = profile(house: AiringRoom.new(swings: [144, 36]),
                        setup: setup(influences: [aircon]))
        assert_in_delta TRIANGULAR, found.own[600].sigma, 0.1 * TRIANGULAR
    end

    private

    def setup(**settings)
        Sensorium::Setup.new(quantity: Sensorium::Presets::TEMPERATURE,
                             places: %w[ceiling], **settings)
    end

    def learn(given = setup, house: AiringRoom.new)
        Sensorium::Transient.learn(house, given, from: START,
                                                 to: START + SPAN)
    end

    # [own, relative] σ over ten minutes.
    def sigmas(found) = [found.own, found.relative].map { it[600].sigma }

    def profile(device = "s", house: AiringRoom.new, setup: self.setup)
        learn(setup, house:).find { it.device == device }
    end
end
