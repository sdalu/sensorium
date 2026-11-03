# frozen_string_literal: true

require "test_helper"
require "support/noisy_room"

# Whether the fused value is as far from the truth as its σ says.
# NoisyRoom knows its truth: learned on its first twenty days, fused
# hourly on the last ten, z = (fused − truth) / σ should vary by about
# 1 over the 240 hours. The band's top, 1.3, is the 99.9 % point of the
# variance of 240 standard normals (χ² with 239 degrees of freedom): a
# σ more overconfident than that is not chance. Its bottom, 0.3, is
# RecordedRoomTest's: the reference's error is in every sensor's σ (the
# spread against it) as well as in its own, so the fused σ errs wide,
# by up to 1.8 times here.
# The reference (the ceiling) is noisy too, and nothing sets its σ: a
# reference as noisy as the quantity's σ says (0.1) fuses honestly as
# it is; one three times noisier is learned (Collocation), given to the
# Fusion with the offsets, and fuses honestly once it is.
class TruthCalibrationTest < Minitest::Test
    NOISE = { "ceil" => [0.0, 0.1], "wall" => [0.5, 0.2],
              "door" => [-0.3, 0.3], "lamp" => [0.2, 0.15] }.freeze
    NOISY = NOISE.merge("ceil" => [0.0, 0.3]).freeze
    SETUP = Sensorium::Presets.room
    SPAN  = { from: NoisyRoom::START,
              to: NoisyRoom::START + (20 * 86_400) }.freeze
    TO    = NoisyRoom::START + (NoisyRoom::SIZE * NoisyRoom::STEP)
    BAND  = (0.3..1.3)

    def test_the_fused_value_is_as_far_from_the_truth_as_its_sigma_says
        zs, = scored(NoisyRoom.new(NOISE))
        assert_equal 240, zs.size
        assert_includes BAND, var(zs)
    end

    def test_a_noisier_reference_is_learned
        zs, sigmas = scored(NoisyRoom.new(NOISY), learned: true)
        assert_includes BAND, var(zs)
        assert_in_delta 0.3, sigmas.sum / sigmas.size, 0.15 * 0.3
    end

    private

    # [[z], [the reference's σ]] over the last ten days, hourly.
    def scored(room, learned: false)
        fusion = fusion(room, learned)
        instants.each_with_object([[], []]) do |at, (zs, sigmas)|
            fused = fusion.location("room", snapshot(room, at))
            zs << ((fused.value - room.truth_at(at)) / fused.sigma)
            sigmas << reference(fused).sigma
        end
    end

    # The Fusion of what was learned over the first twenty days; learned
    # true: with the Collocation, for the reference's σ.
    def fusion(room, learned)
        history = Sensorium::History.load(room, SETUP, **SPAN)
        found = Sensorium::Learner.new(room, SETUP, history:).learn
        collocations = Sensorium::Collocation.learn(
            room, SETUP, history:, offsets: found.offsets
        )
        Sensorium::Fusion.new(SETUP, offsets: found.offsets,
                                     shifts: found.shifts,
                                     collocations: learned ? collocations : [])
    end

    def snapshot(room, at) = Sensorium::Snapshot.from(room, SETUP, at:)

    def reference(fused) = fused.parts.find { it.part.device == "ceil" }.part

    def instants
        (SPAN[:to].to_i...TO.to_i).step(3600).map { Time.at(it).utc }
    end

    def var(zs)
        mean = zs.sum / zs.size
        zs.sum { (it - mean)**2 } / (zs.size - 1)
    end
end
