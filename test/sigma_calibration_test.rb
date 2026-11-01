# frozen_string_literal: true

require "test_helper"
require "support/noisy_room"

# Whether the σ the Fusion gives each part is honest: learned on the
# room's first twenty days, each part is left out in turn on the last
# ten, hourly, and compared with what the others fuse to; z = d /
# √(σk² + σf²) should vary by about 1. The ceiling, the reference, is
# noisy too (σ 0.1), and a sensor's σ is the spread of its difference
# to it, the reference's noise counted in: σ errs wide, var(z) ≈ 0.76
# here. The band refuses an overconfident σ (above 1.25) and one
# grossly wide (below 0.6).
class SigmaCalibrationTest < Minitest::Test
    NOISE = { "ceil" => [0.0, 0.1], "wall" => [0.5, 0.2],
              "door" => [-0.3, 0.3], "lamp" => [0.2, 0.15] }.freeze
    SETUP = Sensorium::Presets.room
    SPLIT = NoisyRoom::START + (20 * 86_400)
    TO    = NoisyRoom::START + (NoisyRoom::SIZE * NoisyRoom::STEP)
    BAND  = (0.6..1.25)

    def setup
        @zs = self.class.z_scores
    end

    def test_each_part_is_as_far_as_its_sigma_says
        @zs.each do |device, zs|
            assert_includes BAND, var(zs), device
        end
    end

    def test_every_part_is_scored
        assert_equal NOISE.keys.sort, @zs.keys.sort
        assert(@zs.values.all? { it.size >= 200 })
    end

    # { device => [z] }, once for the class.
    def self.z_scores
        @z_scores ||= begin
            room = NoisyRoom.new(NOISE)
            fusion = fusion(room)
            instants.each_with_object(Hash.new { |h, k| h[k] = [] }) do |at, zs|
                parts(fusion, room, at).then { scored(it, zs) }
            end
        end
    end

    def self.instants
        (SPLIT.to_i...TO.to_i).step(3600).map { Time.at(it).utc }
    end

    def self.fusion(room)
        learned = Sensorium::Learner.new(room, SETUP, from: NoisyRoom::START,
                                                      to: SPLIT).learn
        Sensorium::Fusion.new(SETUP, offsets: learned.offsets,
                                     shifts: learned.shifts)
    end

    def self.parts(fusion, room, at)
        snapshot = Sensorium::Snapshot.from(room, SETUP, at:)
        fusion.location("room", snapshot).parts.map(&:part).select(&:value)
    end

    def self.scored(parts, zs)
        parts.each { |part| zs[part.device] << z(part, parts - [part]) }
    end

    def self.z(part, others)
        value, sigma = Sensorium::Combine.robust(others,
                                                 SETUP.quantity.robust_nu)
        (part.value - value) / Math.sqrt((part.sigma**2) + (sigma**2))
    end

    private

    def var(zs)
        mean = zs.sum / zs.size
        zs.sum { (it - mean)**2 } / (zs.size - 1)
    end
end
