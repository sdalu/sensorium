# frozen_string_literal: true

require "test_helper"
require "support/airing_room"
require "support/dynamic_room"
require "support/fake_house"

# One History shared by the four learners: read once from the source,
# and each learner's result from it the one it finds loading alone,
# on FakeHouse, DynamicRoom and AiringRoom.
class HistoryTest < Minitest::Test
    TRANSIENT = Sensorium::Influence::Transient.new

    # A source counting what it is asked: readings, and events per
    # influence.
    class Counting
        attr_reader :reads, :events_of

        def initialize(inner)
            @inner     = inner
            @reads     = 0
            @events_of = Hash.new(0)
        end

        def sensors(quantity) = @inner.sensors(quantity)

        def readings(*)
            @reads += 1
            @inner.readings(*)
        end

        def events(name, from, to)
            @events_of[name] += 1
            @inner.events(name, from, to)
        end
    end

    def test_one_history_reads_the_source_once
        source = Counting.new(FakeHouse.new)
        shared(source, house_setup, span(FakeHouse))
        assert_equal 1, source.reads
        assert_equal %w[heating aircon], source.events_of.keys
        assert_equal [1], source.events_of.values.uniq
    end

    def test_the_fake_house_learns_alike
        found = same(FakeHouse.new, house_setup, span(FakeHouse))
        refute_empty found[:learned].offsets
        refute_empty found[:collocations]
        refute_empty found[:profiles]
    end

    def test_a_dynamic_room_learns_alike
        setup = room_setup(outside: "outside",
                           influences: [DynamicRoom::HEATING,
                                        DynamicRoom::AIRCON, TRANSIENT])
        room = DynamicRoom.new(FakeHouse::START, 30 * 144, aircon: true)
        found = same(room, setup, [FakeHouse::START,
                                   FakeHouse::START + (30 * 86_400)])
        refute_empty found[:models]
    end

    def test_an_airing_room_learns_alike
        setup = room_setup(influences: [TRANSIENT], rate: false, gain: false,
                           transient_rate: 12, min_samples: 200)
        found = same(AiringRoom.new(airings: [16, 5]), setup,
                     span(AiringRoom))
        refute_empty found[:learned].offsets
        refute_empty found[:profiles]
    end

    def test_the_history_holds_the_span
        history = Sensorium::History.load(FakeHouse.new, house_setup,
                                          **span_of(span(FakeHouse)))
        assert_equal span(FakeHouse), [history.from, history.to]
        assert_equal ["ceil-a"], history.references.fetch("room-a")
    end

    # A sole reference's carried series, found once.
    def test_the_carried_reference_is_kept
        history = Sensorium::History.load(FakeHouse.new, house_setup,
                                          **span_of(span(FakeHouse)))
        carried = history.carried("room-a")
        assert_same carried, history.carried("room-a")
        assert_equal history.carried_of("room-a", "ceil-a"), carried
        assert_operator history.rates("room-a").size, :>, 1000
    end

    private

    # Minitest's setup is a hook: this one is named apart.
    def room_setup(**)
        Sensorium::Setup.new(quantity: Sensorium::Presets::TEMPERATURE,
                             places: %w[ceiling], **)
    end

    def house_setup
        room = Sensorium::Presets.room
        room.with(influences: room.influences + [TRANSIENT])
    end

    def span(fixture)
        [fixture::START, fixture::START + (fixture::DAYS * 86_400)]
    end

    def span_of((from, to)) = { from:, to: }

    # Every learner's result from one History, and loading alone,
    # compared field by field.
    def same(source, setup, span)
        found = shared(source, setup, span)
        alone = alone(source, setup, span, found[:learned].offsets)
        assert_equal fields(alone), fields(found)
        found
    end

    # { name => [Hash] } of every result, each field by field.
    def fields(found)
        learned = found[:learned]
        found.except(:learned)
             .merge(offsets: learned.offsets, shifts: learned.shifts)
             .transform_values { |list| list.map(&:to_h) }
    end

    def shared(source, setup, span)
        history = Sensorium::History.load(source, setup, **span_of(span))
        profiles = Sensorium::Transient.learn(source, setup, history:)
        learned = Sensorium::Learner.new(source, setup, history:,
                                                        transients: profiles)
                                    .learn
        { profiles:, learned:,
          models: Sensorium::Dynamics.learn(source, setup, history:),
          collocations: Sensorium::Collocation.learn(
              source, setup, offsets: learned.offsets, history:
          ) }
    end

    def alone(source, setup, span, offsets)
        span = span_of(span)
        { profiles: Sensorium::Transient.learn(source, setup, **span),
          learned: Sensorium::Learner.new(source, setup, **span).learn,
          models: Sensorium::Dynamics.learn(source, setup, **span),
          collocations: Sensorium::Collocation.learn(source, setup,
                                                     offsets:, **span) }
    end
end
