# frozen_string_literal: true

require "test_helper"

# A threshold's changes are differences of float readings (and of bin
# means of them): one physical step reads as several floats a few ulps
# apart. The tie rule and the raise of a 0 quantile see them as one
# change, as a Threshold judges them.
class TransientFloatsTest < Minitest::Test
    SETUP = Sensorium::Presets.room

    # As the recorded room's wall sensor (own, 600 s, fall): six falls of
    # 0.55 °C past six larger ones, one read 20.0 -> 19.45, five 20.15 ->
    # 19.6. "A threshold that several changes sit at ... moves a millionth
    # past them too, when leaving them out of those beyond comes nearer
    # the rate" (README, Transients): six at -0.55 with six past it and
    # six allowed, they are left out together; one 0.55 °C fall is not an
    # event where another is.
    def test_one_step_is_judged_the_same_whatever_its_floats
        one = 19.45 - 20.0
        other = 19.6 - 20.15
        changes = ([0.0] * 4300) + [-2.05, -1.35, -1.25, -0.95, -0.6, -0.6] +
                  [one] + ([other] * 5) + ([0.1] * 6)
        threshold = Sensorium::Transient.threshold(changes, SETUP)
        assert_equal threshold.beyond(other).nil?, threshold.beyond(one).nil?,
                     "fall #{threshold.fall}: #{one} and #{other}"
    end

    # A sensor that almost never changes: its 0 quantile "is raised to the
    # sensor's smallest change that is not 0, a millionth past it, so a
    # single step is not an event" (README, Transients). A bin of three
    # equal readings beside a bin of one gives a change of 1.8e-15, and
    # a single 0.1 step becomes an event of z 5.6e13.
    def test_a_single_step_is_no_event_beside_a_bin_means_noise
        changes = ([0.0] * 1400) + [noise, 0.1]
        threshold = Sensorium::Transient.threshold(changes, SETUP)
        assert_nil threshold.beyond(0.1), "rise #{threshold.rise}"
    end

    private

    # The change between a bin of three readings of 15.2 and a bin of
    # one.
    def noise
        at = Time.utc(2026, 1, 10)
        readings = [0, 100, 200, 600].map do |seconds|
            Sensorium::Reading.new(time: at + seconds, location: "room",
                                   device: "d", value: 15.2)
        end
        first, second = Sensorium::Series.new(SETUP.bin).means(readings).values
        second - first
    end
end
