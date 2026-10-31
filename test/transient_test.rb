# frozen_string_literal: true

require "test_helper"
require "support/airing_room"

# Transient.learn: each sensor's thresholds of change over each window,
# for a fall and a rise, its own and against its reference, in
# AiringRoom: the quantiles of its changes a target rate of false
# alarms a day leaves beyond.
class TransientTest < Minitest::Test
    START = AiringRoom::START
    SPAN  = AiringRoom::DAYS * 86_400

    # Uniform noise of ±0.05 on each reading: a change is the
    # difference of two, within ±0.1. At 0.2 a day of 144 bins, a
    # threshold leaves two changes in 1440 beyond it: near the edge.
    def test_a_sensors_own_thresholds_are_its_changes_tails
        own = profile.own
        assert_equal [600, 1200], own.keys
        own.each_value do |threshold|
            assert_operator threshold.fall, :<, -0.08
            assert_operator threshold.rise, :>, 0.08
            assert_operator [-threshold.fall, threshold.rise].max, :<=, 0.1
        end
    end

    # s - ceil holds both noises: its change is within ±0.2.
    def test_the_relative_thresholds_hold_the_references_noise_too
        own = profile.own[600]
        relative = profile.relative[600]
        assert_operator relative.rise, :>, own.rise
        assert_operator relative.fall, :<, own.fall
    end

    def test_a_reference_has_no_relative_thresholds
        ceil = profile("ceil")
        refute_empty ceil.own
        assert_empty ceil.relative
    end

    def test_a_profile_says_what_it_is_of
        assert_equal %w[room s temperature all],
                     profile.to_h.values_at(:location, :device, :quantity,
                                            :regime)
    end

    # The whole room moving widens the own thresholds; against the
    # reference, s is as calm as ever.
    def test_a_room_wide_change_widens_only_the_own_thresholds
        found = rises(profile(house: AiringRoom.new(wave: 3.0)))
        calm = rises(profile)
        assert_operator found.first, :>, 1.5 * calm.first
        assert_in_delta calm.last, found.last, 1e-9
    end

    # A higher rate leaves more changes beyond: the thresholds narrow.
    def test_a_higher_rate_narrows_the_thresholds
        wide = profile.own[600]
        narrow = profile(setup: setup(transient_rate: 20)).own[600]
        assert_operator narrow.rise, :<, wide.rise
        assert_operator narrow.fall, :>, wide.fall
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
        assert_operator found.own[600].rise, :<=, 0.1
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

    # [own, relative] rise thresholds over ten minutes.
    def rises(found) = [found.own, found.relative].map { it[600].rise }

    def profile(device = "s", house: AiringRoom.new, setup: self.setup)
        learn(setup, house:).find { it.device == device }
    end
end
