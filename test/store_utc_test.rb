# frozen_string_literal: true

require "test_helper"
require "sensorium/store/sequel"
require "support/winter"

# README (Stores): a time Store::Sequel keeps "is stored and read back as
# UTC, whether Sequel converts times ... or not, and independently of the
# database's own timezone setting".
class StoreUtcTest < Minitest::Test
    ZONES = [nil, :utc, :local].freeze

    # 02:30 UTC on 2026-03-29 is a valid instant; as a Europe/Paris wall
    # clock (the spring-forward gap, 02:00-03:00 local) it does not exist.
    def test_a_time_in_the_spring_gap_round_trips
        at = Time.utc(2026, 3, 29, 2, 30)
        with_tz("Europe/Paris") do
            store = Sensorium::Store::Sequel.new(Sequel.sqlite)
            assert_equal at, track_at(store, at)
            assert_equal at, learned_at(store, at)
        end
    end

    # The database's zone UTC: Sequel parses the text as local time too.
    def test_a_time_in_the_spring_gap_round_trips_with_the_database_in_utc
        at = Time.utc(2026, 3, 29, 2, 30)
        with_tz("Europe/Paris") do
            ZONES.each do |application|
                with_sequel_zones(database: :utc, application:) do
                    assert_round_trip(at, application.inspect)
                end
            end
        end
    end

    # Sequel's application in UTC, the database's zone unset.
    def test_a_time_round_trips_with_the_application_in_utc
        at = Time.utc(2026, 1, 5, 12)
        with_tz("Europe/Paris") do
            with_sequel_zones(database: nil, application: :utc) do
                store = Sensorium::Store::Sequel.new(Sequel.sqlite)
                assert_equal at, track_at(store, at)
                assert_equal at, learned_at(store, at)
            end
        end
    end

    def test_a_time_round_trips_whatever_sequels_zones
        at = Time.utc(2026, 1, 5, 12, 0, 0.5r)
        with_tz("Europe/Paris") do
            ZONES.product(ZONES).each do |database, application|
                with_sequel_zones(database:, application:) do
                    assert_round_trip(at, [database, application].inspect)
                end
            end
        end
    end

    private

    def assert_round_trip(at, message)
        store = Sensorium::Store::Sequel.new(Sequel.sqlite)
        assert_equal at, track_at(store, at), message
        assert_equal at, learned_at(store, at), message
    end

    def track_at(store, at)
        track = Sensorium::Track.new(
            location: "room", device: "tado", quantity: "temperature",
            regime: "winter", reference: "ceil", constant: -1.0, plain: -1.0,
            delta: 0.0, variance: 0.01, cusum_up: 0.0, cusum_down: 0.0,
            at:, state: :ok
        )
        store.keep_tracks("temperature", { %w[room tado] => track })
        store.tracks("temperature")[%w[room tado]].at
    end

    def learned_at(store, at)
        store.keep(Winter.learned, from: at, to: at, at:)
        store.learned("temperature")["winter"].last
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
