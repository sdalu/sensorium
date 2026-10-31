# frozen_string_literal: true

require "test_helper"
require "support/fusion_helpers"

# Fusion with the room's references set (FusionHelpers' room).
class FusionReferencesTest < Minitest::Test
    include FusionHelpers

    # Several references: each corrected to their mean, none raw.
    def test_several_references_are_each_corrected
        fusion = Sensorium::Fusion.new(Sensorium::Presets.room,
                                       offsets: both, shifts: [],
                                       locations: room(%w[ceil plain]))
        fused = fusion.location("room", snapshot("room", { "ceil" => 19.8,
                                                           "plain" => 20.2,
                                                           "tado" => 18.8 }))
        assert_equal "ceil+plain", fused.reference
        assert_in_delta 20.0, fused.value
        assert_in_delta 20.0, part(fused, "ceil").part.value
    end

    # Learned against the ceiling sensor, so not against another.
    def test_offsets_against_other_references_do_not_count
        fused = fuse({ "ceil" => 20.0, "tado" => 19.0, "airzone" => 21.0 },
                     locations: room(%w[airzone]))
        assert_equal "not learned", note(fused, "tado")
        assert_in_delta 21.0, fused.value
    end

    private

    # Learned against the mean of "ceil" and "plain".
    def both
        [offset("ceil", -0.2, 0.05), offset("plain", 0.2, 0.05),
         offset("tado", -1.2, 0.25)].map { it.with(reference: "ceil+plain") }
    end

    def room(references)
        { "room" => Sensorium::Location.new(name: "room", references:) }
    end
end
