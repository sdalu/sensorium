# frozen_string_literal: true

module Sensorium
    module Store
        class Sequel
            # The tables of what is followed between two learnings: the
            # Tracker's tracks, and the Regressions with theirs.
            module Schema
                module_function

                def tracks(t)
                    key(t)
                    %i[reference state].each { t.String it, null: false }
                    %i[constant plain].each { t.Float it }
                    floats(t, %i[delta variance cusum_up cusum_down])
                    t.Float :block_sum
                    t.Float :block_noise
                    t.Integer :block_count
                    t.Time :block_at
                    t.Time :tracked_at, null: false
                    t.primary_key %i[location device quantity]
                end

                # A Regression's terms as JSON, { name => term }.
                def regressions(t)
                    %i[name quantity regime].each do |name|
                        t.String name, null: false
                    end
                    t.Float :constant, null: false
                    t.String :terms, text: true, null: false
                    widths(t)
                    floats(t, %i[plain plain_p10 plain_p90])
                    t.Float :block_share
                    t.primary_key %i[name quantity regime]
                end

                def regression_tracks(t)
                    %i[name quantity regime state].each do |name|
                        t.String name, null: false
                    end
                    floats(t, %i[constant plain delta variance cusum_up
                                 cusum_down block_sum block_noise])
                    t.Integer :block_count, null: false
                    t.Time :block_at
                    t.Time :tracked_at, null: false
                    t.primary_key %i[name quantity]
                end
            end
        end
    end
end
