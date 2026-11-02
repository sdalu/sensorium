# frozen_string_literal: true

require "test_helper"
require "support/renamed_store"
require "sensorium/store/sequel"
require "support/winter"

# The same behaviour from each store: an Offset comes back as kept,
# settings are set and reset (what a learning replaces:
# store_keep_test.rb).
module StoreBehaviour
    def test_a_learning_comes_back
        keep(learned)
        assert_equal sorted(learned.offsets),
                     sorted(@store.offsets("temperature"))
        assert_equal learned.shifts.size, @store.shifts("temperature").size
    end

    def test_a_learning_is_kept_by_quantity_and_regime
        keep(learned)
        assert_empty @store.offsets("humidity")
        assert_equal %w[winter], @store.learned("temperature").keys
    end

    def test_a_location_is_set_and_reset
        @store.set_location("temperature", "blue",
                            { references: %w[a b], sigma: 0.2 })
        blue = @store.locations("temperature").fetch("blue")
        assert_equal %w[a b], blue.references
        assert_in_delta 0.2, blue.sigma
        @store.set_location("temperature", "blue", { sigma: nil })
        blue = @store.locations("temperature").fetch("blue")
        assert_nil blue.sigma
        assert_equal %w[a b], blue.references
        assert_empty @store.locations("humidity")
    end

    def test_a_track_is_kept_by_its_key_and_leaves_the_others
        tado = { %w[room tado] => track(:drifting) }
        @store.keep_tracks("temperature", tado)
        assert_equal tado, @store.tracks("temperature")
        assert_empty @store.tracks("humidity")
        airzone = { %w[room airzone] => track(:jumped, device: "airzone") }
        @store.keep_tracks("temperature", airzone)
        assert_equal tado.merge(airzone), @store.tracks("temperature")
        replaced = { %w[room tado] => track(:ok) }
        @store.keep_tracks("temperature", replaced)
        assert_equal replaced.merge(airzone), @store.tracks("temperature")
    end

    def test_a_references_track_comes_back
        tracks = { %w[room ceil] => track(:jumped, device: "ceil")
                                    .with(constant: nil, plain: nil) }
        @store.keep_tracks("temperature", tracks)
        assert_equal tracks, @store.tracks("temperature")
    end

    def test_a_locations_deltas_are_set_and_reset
        @store.set_location("temperature", "blue",
                            { deltas: { "tado" => 0.1, "plain" => 0.5 } })
        blue = @store.locations("temperature").fetch("blue")
        assert_equal({ "tado" => 0.1, "plain" => 0.5 }, blue.deltas)
        @store.set_location("temperature", "blue", { deltas: nil })
        assert_empty @store.locations("temperature").fetch("blue").deltas
    end

    private

    # A track in the middle of a block of four readings.
    def track(state, device: "tado", at: FakeHouse::START)
        Sensorium::Track.new(location: "room", device:,
                             quantity: "temperature", regime: "winter",
                             reference: "ceil", constant: -1.0, plain: -1.0,
                             delta: 0.125, variance: 0.0025, cusum_up: 1.5,
                             cusum_down: 0.0, block_sum: 0.375,
                             block_noise: 0.25, block_count: 4,
                             block_at: at - 3600, at:, state:)
    end

    def learned = Winter.learned

    def keep(learned)
        @store.keep(learned, from: FakeHouse::START, to: FakeHouse::START,
                             at: FakeHouse::START)
    end

    def sorted(offsets)
        offsets.sort_by { [it.location, it.device, it.regime] }
    end
end

class MemoryStoreTest < Minitest::Test
    include StoreBehaviour

    def setup = @store = Sensorium::Store::Memory.new
end

class SequelStoreTest < Minitest::Test
    include StoreBehaviour

    def setup
        @store = Sensorium::Store::Sequel.new(Sequel.sqlite)
    end

    def test_without_migrate_no_table_is_made
        db = Sequel.sqlite
        Sensorium::Store::Sequel.new(db, migrate: false)
        assert_empty db.tables
    end

    def test_the_tables_can_be_named
        db = Sequel.sqlite
        Sensorium::Store::Sequel.new(db, tables: { locations: :sensor_rooms })
        assert db.table_exists?(:sensor_rooms)
        refute db.table_exists?(:sensor_locations)
    end

    def test_a_learnings_block_shares_come_back
        keep(learned)
        assert(learned.offsets.all?(&:block_share))
        assert_equal learned.offsets.map(&:block_share).sort,
                     @store.offsets("temperature").map(&:block_share).sort
    end

    # Tables made before the blocks: opened with migrate, they get the
    # columns, and a track kept before them starts a block afresh.
    def test_tables_made_before_the_blocks_get_their_columns
        db = Sequel.sqlite
        Sensorium::Store::Sequel.new(db)
        older(db)
        db[:sensor_tracks].insert(old_row)
        store = Sensorium::Store::Sequel.new(db)
        assert_includes db.schema(:sensor_offsets).map(&:first), :block_share
        kept = store.tracks("temperature").fetch(%w[room tado])
        assert_equal [0.0, 0.0, 0, nil],
                     kept.to_h.values_at(:block_sum, :block_noise,
                                         :block_count, :block_at)
    end

    def test_the_tracks_table_can_be_named
        db = Sequel.sqlite
        Sensorium::Store::Sequel.new(db, tables: { tracks: :tracking })
        assert db.table_exists?(:tracking)
        refute db.table_exists?(:sensor_tracks)
    end

    # A moment in the autumn hour Europe/Paris repeats (2026-10-25,
    # 00:30 UTC is 02:30 CEST, then again as 02:30 CET an hour later):
    # kept and read back under that zone, a track's and a learning's
    # time must stay the instant given.
    def test_times_round_trip_through_the_repeated_dst_hour
        at = Time.utc(2026, 10, 25, 0, 30)
        with_tz("Europe/Paris") { assert_dst_round_trip(at) }
    end

    # Sequel converting, as an application set up so does (the
    # database in UTC, the application local): the Time read back is
    # already the instant, in local time.
    def test_times_round_trip_where_sequel_converts
        with_tz("Europe/Paris") do
            with_sequel_zones(database: :utc, application: :local) do
                @store = Sensorium::Store::Sequel.new(Sequel.sqlite)
                [Time.utc(2026, 1, 5), Time.utc(2026, 7, 1, 12),
                 Time.utc(2026, 10, 25, 0, 30)]
                    .each { assert_dst_round_trip(it) }
            end
        end
    end

    private

    # The tables as they were before the blocks.
    def older(db)
        db.alter_table(:sensor_offsets) { drop_column :block_share }
        db.alter_table(:sensor_tracks) do
            %i[block_sum block_noise block_count block_at].each do |name|
                drop_column name
            end
        end
    end

    def old_row
        track(:ok).to_h.except(:at, :block_sum, :block_noise, :block_count,
                               :block_at)
                  .merge(tracked_at: FakeHouse::START, state: "ok")
    end

    def assert_dst_round_trip(at)
        assert_equal at, track_at(at)
        assert_equal at, learned_at(at)
    end

    def track_at(at)
        @store.keep_tracks("temperature", { %w[room tado] => track(:ok, at:) })
        @store.tracks("temperature")[%w[room tado]].at
    end

    def learned_at(at)
        @store.keep(learned, from: at, to: at, at:)
        @store.learned("temperature")["winter"].last
    end

    def with_tz(name)
        before = ENV.fetch("TZ", nil)
        ENV["TZ"] = name
        yield
    ensure
        ENV["TZ"] = before
    end

    def with_sequel_zones(database:, application:)
        before = [Sequel.database_timezone, Sequel.application_timezone]
        Sequel.database_timezone = database
        Sequel.application_timezone = application
        yield
    ensure
        Sequel.database_timezone, Sequel.application_timezone = before
    end
end

class RenamedStoreTest < Minitest::Test
    include StoreBehaviour

    def setup = @store = RenamedStore.new
end

# A caller's own tables, their columns named its way.
class StoreColumnsTest < Minitest::Test
    def test_the_tables_take_the_names_given
        db = Sequel.sqlite
        RenamedStore.new(db)
        columns = db.schema(:sensor_offsets).map(&:first)
        assert_includes columns, :zone
        assert_includes columns, :made_at
        refute_includes columns, :location
    end

    # Made by the caller (here a first store), opened without
    # migrating: what one kept, the other reads.
    def test_a_callers_tables_are_read_as_they_are
        db = Sequel.sqlite
        RenamedStore.new(db).keep(Winter.learned, from: Time.utc(2026, 1, 5),
                                                  to: Time.utc(2026, 1, 15))
        store = Sensorium::Store::Sequel.new(
            db, columns: RenamedStore::COLUMNS, migrate: false
        )
        assert_equal Winter.learned.offsets.size,
                     store.offsets("temperature").size
    end

    def test_an_unknown_column_is_refused
        error = assert_raises(ArgumentError) do
            Sensorium::Store::Sequel.new(Sequel.sqlite,
                                         columns: { locaton: :zone })
        end
        assert_match(/locaton/, error.message)
    end

    def test_a_name_another_column_has_is_refused
        assert_raises(ArgumentError) do
            Sensorium::Store::Sequel.new(Sequel.sqlite,
                                         columns: { location: :device })
        end
    end
end
