# frozen_string_literal: true

require "test_helper"

# A source may tell a Switch's events as text: "off", "0" and "false"
# (any case, trimmed) are off, as false, nil and 0 are; a number is
# read as its number; any other text is on, as any other value.
class SwitchTextTest < Minitest::Test
    SWITCH = Sensorium::Influence::Switch.new(name: "heating")

    def test_texts_that_say_off
        ["off", "0", "false", " OFF ", "False", "0.0", "-1"].each do |text|
            refute SWITCH.on?(text), text.inspect
        end
    end

    def test_texts_that_say_on
        ["on", "1", "true", "cooling", " On", "2.5"].each do |text|
            assert SWITCH.on?(text), text.inspect
        end
    end

    def test_values_as_before
        [false, nil, 0, -1.0].each { refute SWITCH.on?(it), it.inspect }
        [true, 1, 0.5, :on].each { assert SWITCH.on?(it), it.inspect }
    end
end
