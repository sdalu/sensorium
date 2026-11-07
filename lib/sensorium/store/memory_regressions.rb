# frozen_string_literal: true

module Sensorium
    module Store
        # The Regressions of Store::Memory, and their tracks.
        module MemoryRegressions
            def regressions(quantity)
                @regressions.select { it.quantity == quantity }
            end

            def keep_regressions(quantity, list)
                Store.same_quantity!(quantity, list)
                @regressions = replaced(@regressions, quantity, list,
                                        %i[name regime])
            end

            def regression_tracks(quantity)
                @regression_tracks.fetch(quantity, {})
            end

            def keep_regression_tracks(quantity, tracks)
                Store.same_quantity!(quantity, tracks.values)
                @regression_tracks[quantity] =
                    regression_tracks(quantity).merge(tracks).freeze
            end

            def forget_regression(quantity, name)
                @regressions.reject! do |one|
                    one.quantity == quantity && one.name == name
                end
                @regression_tracks[quantity] =
                    regression_tracks(quantity).except(name).freeze
            end
        end
    end
end
