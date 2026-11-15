# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "sensorium/store/sequel"

# Two processes setting the same location at once (a consumer setting
# its σ while another sets its drift). The interleaving is forced: B
# sets its setting just as A opens its transaction. Neither is lost.
class LocationRaceTest < Minitest::Test
    def setup = @dir = Dir.mktmpdir

    def teardown
        @opened&.each(&:disconnect)
        FileUtils.remove_entry(@dir)
    end

    def test_a_setting_set_meanwhile_is_kept
        first = store
        first.set_location("temperature", "blue", { references: ["ceil"] })
        interleave(@opened.last) do
            store.set_location("temperature", "blue", { sigma: 0.2 })
        end
        first.set_location("temperature", "blue", { drift: 0.05 })
        blue = store.locations("temperature").fetch("blue")
        assert_equal [["ceil"], 0.2, 0.05],
                     [blue.references, blue.sigma, blue.drift]
    end

    private

    def store
        db = Sequel.sqlite(File.join(@dir, "store.db"))
        (@opened ||= []) << db
        Sensorium::Store::Sequel.new(db)
    end

    # Runs the block once, just as db opens its next transaction.
    def interleave(db, &between)
        db.define_singleton_method(:transaction) do |*args, **opts, &body|
            between&.call
            between = nil
            super(*args, **opts, &body)
        end
    end
end
