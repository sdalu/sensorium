# frozen_string_literal: true

require "test_helper"
require "support/tracker_helpers"

# A reference's block share is the largest of its location's Offsets';
# one of them may have none (too few blocks learned).
class ReferenceShareTest < Minitest::Test
    include TrackerHelpers

    def test_an_offset_without_a_block_share_does_not_stop_the_reference
        mixed = offsets.each_with_index.map do |offset, i|
            offset.with(block_share: i.zero? ? nil : 0.8)
        end
        tracker = Sensorium::Tracker.new(SETUP, offsets: mixed)
        tracks = tracker.update({}, fusion.location("room", moment(0)))
        assert tracks.key?(%w[room ceil])
    end
end
