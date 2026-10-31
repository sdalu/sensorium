# frozen_string_literal: true

require "test_helper"
require "support/house_knowledge"

# A Tick over 48 hours of FakeHouse, every ten minutes from its third
# day (the aircon running in room-a the first 30 hours), against the
# recipe it replaces: a Fusion with the tracks for the value, another
# without them for the Tracker, each given its share of the Knowledge.
# At every tick, the same Fused, the same tracks, the same events.
class TickTest < Minitest::Test
    SETUP = HouseKnowledge::SETUP
    FROM  = FakeHouse::START + (2 * 86_400)
    TICKS = 48 * 6

    def test_a_tick_is_the_two_fusion_recipe
        tick_by_tick do |result, expected|
            assert_equal expected.fused, result.fused
            assert_equal expected.tracks, result.tracks
            assert_equal expected.events, result.events
        end
    end

    # Over the 48 hours tado's track drifts then jumps, Airzone's in
    # room-a jumps, and Airzone's in room-b, of two, is updated to the
    # last tick with the witness: the comparison is not of idle tracks.
    def test_the_hours_compared_are_not_idle
        states = Hash.new { |hash, key| hash[key] = [] }
        last = ticked(states)
        assert_equal %i[drifting jumped], states[%w[room-a tado]].uniq
        assert_includes states[%w[room-a airzone]], :jumped
        assert_equal FROM + ((TICKS - 1) * 600),
                     last.fetch(%w[room-b airzone]).at
    end

    private

    # The tracks after the last tick, each track's state after each
    # tick added to states.
    def ticked(states)
        last = nil
        tick_by_tick do |result, _|
            last = result.tracks
            last.each { |key, track| states[key] << track.state }
        end
        last
    end

    # Yields, at each tick, the Tick's Result and the recipe's.
    def tick_by_tick
        state = [knowledge.tracks, {}]
        TICKS.times do |i|
            snapshot = Sensorium::Snapshot.from(house, SETUP,
                                                at: FROM + (i * 600))
            tracks, previous = state
            result = Sensorium::Tick.new(SETUP, knowledge.with(tracks:))
                                    .call(snapshot, previous:)
            yield result, recipe(tracks, snapshot, previous)
            state = [result.tracks, result.fused]
        end
    end

    # The Result as made before the Tick: two Fusions, a Tracker updated
    # from the Fused made without tracks, a Detector.
    def recipe(tracks, snapshot, previous)
        tracked = fusion(tracks:)
        names = tracked.locations(snapshot)
        Sensorium::Tick::Result.new(
            fused: names.to_h { [it, tracked.location(it, snapshot)] },
            tracks: updated(tracks, names, snapshot, previous),
            events: detector.events(snapshot)
        )
    end

    # The tracks updated from each location's Fused made without tracks.
    def updated(tracks, names, snapshot, previous)
        untracked = fusion
        names.reduce(tracks) do |kept, name|
            tracker.update(kept, untracked.location(name, snapshot),
                           previous: previous[name], snapshot:)
        end
    end

    def fusion(tracks: {})
        Sensorium::Fusion.new(SETUP, offsets: knowledge.offsets,
                                     shifts: knowledge.shifts,
                                     locations: knowledge.locations,
                                     dynamics: knowledge.dynamics, tracks:)
    end

    def tracker
        Sensorium::Tracker.new(SETUP, offsets: knowledge.offsets,
                                      dynamics: knowledge.dynamics,
                                      locations: knowledge.locations,
                                      transients: knowledge.transients)
    end

    def detector
        Sensorium::Transient::Detector.new(
            SETUP, profiles: knowledge.transients,
                   locations: knowledge.locations
        )
    end

    def knowledge = HouseKnowledge.knowledge
    def house = @house ||= FakeHouse.new
end
