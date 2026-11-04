# frozen_string_literal: true

require "test_helper"
require "sensorium/store/sequel"

# A Sequel store opened read_only: true reads what another wrote,
# creates no table, and refuses every write by name, before the
# database sees it.
class StoreReadOnlyTest < Minitest::Test
    def setup
        @db = Sequel.sqlite
        writer = Sensorium::Store::Sequel.new(@db)
        writer.set_location("temperature", "blue", { sigma: 0.2 })
        @store = Sensorium::Store::Sequel.new(@db, read_only: true)
    end

    def test_it_reads_what_was_kept
        assert_in_delta 0.2, @store.locations("temperature")["blue"].sigma
        assert_empty @store.offsets("temperature")
    end

    def test_it_makes_no_table
        db = Sequel.sqlite
        Sensorium::Store::Sequel.new(db, read_only: true)
        assert_empty db.tables
    end

    def test_every_write_is_refused
        Sensorium::Store::Sequel::ReadOnly::WRITES.each do |name|
            error = assert_raises(Sensorium::Store::ReadOnlyError) do
                @store.public_send(name, "temperature", "blue", {})
            end
            assert_match(/\A#{name}:/, error.message)
        end
        assert_in_delta 0.2, @store.locations("temperature")["blue"].sigma
    end

    # A writer added to the store is refused too: every public method
    # that keeps, sets or forgets is in WRITES.
    def test_the_writes_are_all_the_writers
        writers = Sensorium::Store::Sequel.public_instance_methods
                                          .grep(/\A(keep|set_|forget)/)
        assert_equal writers.sort,
                     Sensorium::Store::Sequel::ReadOnly::WRITES.sort
    end
end
