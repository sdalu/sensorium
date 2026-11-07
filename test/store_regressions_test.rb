# frozen_string_literal: true

require "test_helper"
require "support/renamed_store"
require "sensorium/store/sequel"

# Regressions and their tracks come back from each store as kept; a
# later keep replaces those of the same name and regime (a track, of the
# same name); a Regression forgotten goes in every regime, with its
# track.
module StoreRegressionsBehaviour
    AT = Time.utc(2026, 3, 29, 1, 30)

    def test_the_regressions_come_back
        @store.keep_regressions("gas", [regression, regression("summer")])
        assert_equal [regression("summer"), regression], sorted("gas")
    end

    def test_they_are_kept_by_quantity
        @store.keep_regressions("gas", [regression])
        assert_empty @store.regressions("water")
    end

    def test_a_keep_replaces_the_same_name_and_regime
        @store.keep_regressions("gas", [regression, regression("summer")])
        again = regression.with(constant: 11.0, terms: {})
        @store.keep_regressions("gas", [again])
        assert_equal [regression("summer"), again], sorted("gas")
    end

    def test_rows_of_another_quantity_are_refused
        assert_raises(ArgumentError) do
            @store.keep_regressions("water", [regression])
        end
    end

    def test_the_tracks_come_back
        @store.keep_regression_tracks("gas", { "house" => track })
        assert_equal({ "house" => track }, @store.regression_tracks("gas"))
        assert_empty @store.regression_tracks("water")
    end

    def test_a_track_kept_again_replaces_its_own
        @store.keep_regression_tracks("gas", { "house" => track })
        later = track.with(delta: 1.5, at: AT + 86_400)
        @store.keep_regression_tracks("gas", { "house" => later })
        assert_equal({ "house" => later }, @store.regression_tracks("gas"))
    end

    # Kept under another quantity, a store would file it under either.
    def test_a_track_of_another_quantity_is_refused
        assert_raises(ArgumentError) do
            @store.keep_regression_tracks("water", { "house" => track })
        end
        assert_empty @store.regression_tracks("gas")
    end

    def test_a_regression_forgotten
        @store.keep_regressions("gas", [regression, regression("summer")])
        @store.keep_regression_tracks("gas", { "house" => track })
        @store.forget_regression("gas", "house")
        assert_empty @store.regressions("gas")
        assert_empty @store.regression_tracks("gas")
    end

    private

    def sorted(quantity)
        @store.regressions(quantity).sort_by { [it.name, it.regime] }
    end

    def regression(regime = "winter")
        Sensorium::Regression.new(
            name: "house", quantity: "gas", regime:, constant: 12.5,
            terms: { "valve/a" => 0.0333 }, p10: -2.1, p90: 2.3,
            samples: 150, plain: 30.0, plain_p10: -12.0, plain_p90: 14.0,
            block_share: 0.6
        )
    end

    # In the hour the clocks skip in Paris, in a block under way.
    def track
        Sensorium::Track.start(location: nil, device: "house",
                               quantity: "gas", regime: "winter",
                               reference: nil, constant: 12.5, plain: 30.0,
                               variance: 0.04)
                        .with(delta: 0.3, block_sum: 1.2, block_count: 2,
                              block_noise: 0.5, block_at: AT - 86_400, at: AT)
    end
end

class MemoryStoreRegressionsTest < Minitest::Test
    include StoreRegressionsBehaviour

    def setup = @store = Sensorium::Store::Memory.new
end

class SequelStoreRegressionsTest < Minitest::Test
    include StoreRegressionsBehaviour

    def setup = @store = Sensorium::Store::Sequel.new(Sequel.sqlite)

    def test_the_tables_can_be_named
        db = Sequel.sqlite
        Sensorium::Store::Sequel.new(
            db, tables: { regressions: :gas_models,
                          regression_tracks: :gas_tracks }
        )
        assert db.table_exists?(:gas_models)
        assert db.table_exists?(:gas_tracks)
        refute db.table_exists?(:sensor_regressions)
    end
end

class RenamedStoreRegressionsTest < Minitest::Test
    include StoreRegressionsBehaviour

    def setup = @store = RenamedStore.new
end
