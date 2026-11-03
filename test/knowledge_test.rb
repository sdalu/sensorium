# frozen_string_literal: true

require "test_helper"
require "sensorium/store/sequel"
require "support/house_knowledge"
require "support/tracker_helpers"

# A Knowledge comes back from each store as it was kept.
module KnowledgeBehaviour
    KEYS = %i[location device regime influence mode].freeze

    def test_a_knowledge_round_trips
        keep(HouseKnowledge.knowledge)
        found = @store.knowledge("temperature")
        HouseKnowledge.knowledge.to_h.each do |member, kept|
            assert_equal sorted(kept), sorted(found.public_send(member)),
                         member
        end
    end

    def test_another_quantitys_knowledge_is_empty
        keep(HouseKnowledge.knowledge)
        assert_equal Sensorium::Knowledge.new, @store.knowledge("humidity")
    end

    private

    def keep(knowledge)
        learned = Winter.learned
        @store.keep(learned, from: FakeHouse::START, to: FakeHouse::START,
                             at: FakeHouse::START)
        knowledge.locations.each do |name, location|
            @store.set_location("temperature", name,
                                location.to_h.except(:name))
        end
        @store.keep_tracks("temperature", knowledge.tracks)
        @store.keep_dynamics("temperature", knowledge.dynamics)
        @store.keep_transients("temperature", knowledge.transients)
    end

    # Rows in the order of their keys, whatever the store's.
    def sorted(rows)
        return rows unless rows.is_a?(Array)
        rows.sort_by { it.to_h.slice(*KEYS).values.map(&:to_s) }
    end
end

class MemoryKnowledgeTest < Minitest::Test
    include KnowledgeBehaviour

    def setup = @store = Sensorium::Store::Memory.new
end

class SequelKnowledgeTest < Minitest::Test
    include KnowledgeBehaviour

    def setup = @store = Sensorium::Store::Sequel.new(Sequel.sqlite)
end

# The Fusion, the Tracker and the Detector take a Knowledge as they take
# its parts as keywords; not both.
class KnowledgeGivenTest < Minitest::Test
    SETUP = HouseKnowledge::SETUP
    AT    = FakeHouse::START + (4 * 86_400)

    def test_a_fusion_given_a_knowledge
        given = Sensorium::Fusion.new(SETUP, knowledge:)
        keywords = Sensorium::Fusion.new(
            SETUP, **knowledge.to_h.except(:transients)
        )
        assert_equal fused(keywords), fused(given)
    end

    def test_a_tracker_given_a_knowledge
        keywords = Sensorium::Tracker.new(
            SETUP, **knowledge.to_h.except(:shifts, :tracks, :dynamics,
                                           :collocations)
        )
        given = Sensorium::Tracker.new(SETUP, knowledge:)
        assert_equal updated(keywords), updated(given)
    end

    def test_a_detector_given_a_knowledge
        keywords = Sensorium::Transient::Detector.new(
            SETUP, profiles: knowledge.transients,
                   locations: knowledge.locations
        )
        given = Sensorium::Transient::Detector.new(SETUP, knowledge:)
        moment = transient_moment
        refute_empty given.events(moment)
        assert_equal keywords.events(moment), given.events(moment)
    end

    def test_a_knowledge_and_keywords_are_refused
        assert_raises(ArgumentError) do
            Sensorium::Fusion.new(SETUP, knowledge:, offsets: [])
        end
        assert_raises(ArgumentError) do
            Sensorium::Tracker.new(SETUP, knowledge:, offsets: [])
        end
        assert_raises(ArgumentError) do
            Sensorium::Transient::Detector.new(SETUP, knowledge:,
                                                      profiles: [])
        end
    end

    def test_without_either_a_keyword_required_is_missed
        assert_raises(ArgumentError) { Sensorium::Fusion.new(SETUP) }
        assert_raises(ArgumentError) do
            Sensorium::Fusion.new(SETUP, offsets: [])
        end
        assert_raises(ArgumentError) { Sensorium::Tracker.new(SETUP) }
        assert_raises(ArgumentError) do
            Sensorium::Transient::Detector.new(SETUP)
        end
    end

    private

    def knowledge = HouseKnowledge.knowledge

    def snapshot(at = AT)
        Sensorium::Snapshot.from(FakeHouse.new, SETUP, at:)
    end

    # The aircon starting in room-a: Airzone falls to 5 °C.
    def transient_moment = snapshot(FakeHouse::START + (2 * 86_400))

    def updated(tracker)
        moment = snapshot
        fused = Sensorium::Fusion.new(SETUP, knowledge:)
                                 .location("room-a", moment)
        tracker.update(knowledge.tracks, fused, snapshot: moment)
    end

    def fused(fusion)
        moment = snapshot
        fusion.locations(moment).map { fusion.location(it, moment) }
    end
end

# The Tracker given a Fused made with the tracks takes each part as it
# was before its Track was applied: the same tracks as from the Fused
# made without them, though tado's is drifting (its part noted so) and
# Airzone's has jumped (its part left out).
class TrackedFusedTest < Minitest::Test
    include TrackerHelpers

    def test_the_tracker_reads_a_tracked_fused_as_an_untracked_one
        tracks = states(track(10))
        5.times do |i|
            snapshot = moment(10 + i, { "tado" => 19.3, "airzone" => 21.1 })
            tracked = tracked(tracks).location("room", snapshot)
            assert_equal %w[drifting jumped], notes(tracked) if i.zero?
            tracks = same_update(tracks, tracked, snapshot)
        end
    end

    private

    def states(tracks)
        tracks.merge(
            %w[room tado] => tracks.fetch(%w[room tado])
                                   .with(delta: 0.2, state: :drifting),
            %w[room airzone] => tracks.fetch(%w[room airzone])
                                      .with(state: :jumped)
        )
    end

    # The tracks updated from the tracked Fused, asserted the same as
    # from the untracked one.
    def same_update(tracks, tracked, snapshot)
        updated = tracker.update(tracks, tracked)
        assert_equal tracker.update(tracks, fusion.location("room", snapshot)),
                     updated
        updated
    end

    def notes(fused) = %w[tado airzone].map { note(fused, it) }

    def tracked(tracks)
        Sensorium::Fusion.new(SETUP, offsets:, shifts: [], tracks:)
    end
end
