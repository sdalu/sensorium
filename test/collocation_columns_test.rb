# frozen_string_literal: true

require "test_helper"

# Triple collocation needs three series at least: with fewer, no
# series' error is measurable, whatever hands the columns over.
class CollocationColumnsTest < Minitest::Test
    COLUMNS = { "ceil" => [20.0, 20.5, 21.25, 20.75],
                "wall" => [20.5, 20.75, 21.5, 21.5],
                "door" => [19.75, 20.25, 21.0, 20.25] }.freeze

    def test_two_columns_are_not_measurable
        two = COLUMNS.slice("ceil", "wall")
        assert_nil Sensorium::Collocation.variance(two, "ceil")
        assert_equal({ "ceil" => nil, "wall" => nil },
                     Sensorium::Collocation.sigmas(two))
    end

    def test_one_column_is_not_measurable
        one = COLUMNS.slice("ceil")
        assert_equal({ "ceil" => nil }, Sensorium::Collocation.sigmas(one))
    end

    def test_three_columns_are
        assert_kind_of Float, Sensorium::Collocation.variance(COLUMNS, "ceil")
    end
end
