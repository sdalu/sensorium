# frozen_string_literal: true

require "test_helper"

# A location's references named as one ("a+b" for their mean), each
# device's "%" and "+" escaped, so a device named with a "+" (a
# temperature+humidity unit) is one reference, not two.
class ReferenceNamesTest < Minitest::Test
    AT = Time.utc(2026, 1, 10, 12)

    def test_names_go_and_come_back
        [%w[ceil], %w[a b], %w[t+h], %w[t+h ceil], %w[100%]].each do |list|
            name = Sensorium.reference_name(list)
            assert_equal list, Sensorium.references_of(name)
        end
        assert_equal "a+b", Sensorium.reference_name(%w[a b])
        refute_equal Sensorium.reference_name(%w[t+h]),
                     Sensorium.reference_name(%w[t h])
    end

    # Learned against "t+h", references not set: it counts as the
    # reference, as it reads.
    def test_a_learned_reference_named_with_a_plus_counts
        fused = fusion.location("room", snapshot)
        reference = fused.parts.find { it.part.device == "t+h" }
        assert_nil reference.note
        assert_equal Sensorium.reference_name(%w[t+h]), fused.reference
    end

    # Its track is the pinned reference's.
    def test_a_reference_named_with_a_plus_is_tracked
        fused = fusion.location("room", snapshot)
        tracks = Sensorium::Tracker.new(Sensorium::Presets.room,
                                        offsets:).update({}, fused)
        assert_includes tracks.keys, ["room", "t+h"]
    end

    private

    def fusion
        Sensorium::Fusion.new(Sensorium::Presets.room, offsets:, shifts: [])
    end

    def offsets = [offset("tado", -1.0), offset("airzone", 1.0)]

    def offset(device, constant)
        Sensorium::Offset.new(
            location: "room", device:, quantity: "temperature",
            regime: "winter", reference: Sensorium.reference_name(%w[t+h]),
            constant:, switches: {}, gain: nil, neighbour: nil,
            coefficient: nil, p10: -0.25, p90: 0.25, samples: 1000,
            plain: constant, plain_p10: -0.25, plain_p90: 0.25
        )
    end

    def snapshot
        latest = { "t+h" => 20.0, "tado" => 19.0, "airzone" => 21.0 }
                 .to_h do |device, value|
            [["room", device],
             Sensorium::Reading.new(time: AT, location: "room", device:,
                                    value:)]
        end
        Sensorium::Snapshot.new(at: AT, latest:)
    end
end
