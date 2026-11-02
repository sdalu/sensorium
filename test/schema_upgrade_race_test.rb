# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "sensorium/store/sequel"

# Two processes opening the same old database with migrate: true at
# once (two workers started on the new version). The interleaving is
# forced: B upgrades the table right after A has read its columns, and
# before A adds the ones it found missing. A must not fail.
class SchemaUpgradeRaceTest < Minitest::Test
    def test_a_table_upgraded_meanwhile_is_not_upgraded_twice
        Dir.mktmpdir do |dir|
            path = File.join(dir, "store.db")
            first = old(path)
            other = opened(path)
            interleave(first, :sensor_offsets) do
                Sensorium::Store::Sequel.new(other)
            end
            assert_includes upgraded(first), :block_share
        end
    end

    def teardown = @opened&.each(&:disconnect)

    private

    def opened(path) = Sequel.sqlite(path).tap { (@opened ||= []) << it }

    # A store made before block_share: the column dropped.
    def old(path)
        db = opened(path)
        Sensorium::Store::Sequel.new(db)
        db.alter_table(:sensor_offsets) { drop_column :block_share }
        db
    end

    # The offsets table's columns once db has opened the store.
    def upgraded(db)
        Sensorium::Store::Sequel.new(db)
        db.schema(:sensor_offsets, reload: true).map(&:first)
    end

    # Runs the block once, just after db has read table's columns.
    def interleave(db, table, &between)
        db.define_singleton_method(:schema) do |name, opts = {}|
            columns = super(name, opts)
            if name == table && between
                between.call
                between = nil
            end
            columns
        end
    end
end
