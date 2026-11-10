# frozen_string_literal: true

require "test_helper"
require "support/fake_house"

# The bin as a setting: the counts and the transient windows follow it,
# and the constructed house is learned alike with five, ten or twenty
# minutes.
class BinTest < Minitest::Test
    SPAN = { from: FakeHouse::START,
             to: FakeHouse::START + (FakeHouse::DAYS * 86_400) }.freeze

    def test_the_counts_cover_the_same_time
        setup = Sensorium::Presets.room(bin: 300)
        assert_equal [1000, 200, 200],
                     setup.to_h.values_at(:min_samples, :min_shift, :min_part)
        assert_equal [300, 600], setup.transient_windows
    end

    def test_what_is_given_is_kept
        setup = Sensorium::Presets.room(bin: 300, min_samples: 42,
                                        transient_windows: [900])
        assert_equal [42, [900]],
                     setup.to_h.values_at(:min_samples, :transient_windows)
    end

    def test_a_window_not_whole_bins_is_refused
        assert_raises(ArgumentError) do
            Sensorium::Presets.room(bin: 900, transient_windows: [600])
        end
    end

    def test_a_bin_not_whole_seconds_is_refused
        [0, -600, 600.5, nil].each do |bin|
            assert_raises(ArgumentError, bin.inspect) do
                Sensorium::Presets.room(bin:)
            end
        end
    end

    # Alike within 0.01 °C: a constant recentred on the last bins
    # (Setup#recent) takes its median from bins of another width.
    def test_the_house_is_learned_alike_at_every_bin
        first, *others = [300, 600, 1200].map { learned(it) }
        assert_equal 4, first[:offsets].size
        others.each { assert_alike(first, it) }
    end

    private

    def assert_alike(first, other)
        assert_equal first[:profiles], other[:profiles]
        assert_equal first[:offsets].keys, other[:offsets].keys
        first[:offsets].each do |key, constant|
            assert_in_delta constant, other[:offsets][key], 0.0101,
                            key.inspect
        end
    end

    def learned(bin)
        setup = Sensorium::Presets.room(bin:)
        offsets = Sensorium::Learner.new(FakeHouse.new, setup, **SPAN)
                                    .learn.offsets
        profiles = Sensorium::Transient.learn(FakeHouse.new, setup, **SPAN)
        { offsets: offsets.to_h { [key(it), it.constant.round(2)] },
          profiles: profiles.size }
    end

    def key(offset) = offset.to_h.values_at(:location, :device)
end
