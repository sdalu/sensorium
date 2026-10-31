# frozen_string_literal: true

module Sensorium
    module Store
        class Sequel
            # The six tables, created when missing. A caller that keeps
            # its own schema (types, foreign keys) makes them alike and
            # opens the store with migrate: false.
            module Schema
                module_function

                def create(db, tables)
                    %i[offsets shifts locations tracks dynamics
                       collocations].each do |name|
                        db.create_table?(tables.fetch(name)) do
                            Schema.public_send(name, self)
                        end
                    end
                end

                def dynamics(t)
                    %i[location quantity regime].each do |name|
                        t.String name, null: false
                    end
                    floats(t, %i[a c q])
                    %i[rms_hold rms_model].each { t.Float it }
                    t.String :b, text: true, null: false
                    %i[bin steps].each { t.Integer it, null: false }
                    t.primary_key %i[location quantity regime]
                end

                def collocations(t)
                    %i[location quantity regime].each do |name|
                        t.String name, null: false
                    end
                    t.String :sigmas, text: true, null: false
                    t.Integer :samples, null: false
                    t.primary_key %i[location quantity regime]
                end

                def offsets(t)
                    key(t)
                    t.String :reference, null: false
                    t.Float :constant, null: false
                    maps(t)
                    t.String :neighbour
                    widths(t)
                    floats(t, %i[plain plain_p10 plain_p90])
                    learned(t)
                    t.primary_key %i[location device quantity regime]
                end

                # An Offset's maps, as JSON, and its optional numbers.
                def maps(t)
                    %i[switches taus series states].each do |name|
                        t.String name, text: true
                    end
                    %i[gain coefficient rate off_p10 off_p90].each do |name|
                        t.Float name
                    end
                end

                def shifts(t)
                    key(t)
                    %i[influence mode].each { t.String it, null: false }
                    t.Float :shift, null: false
                    widths(t)
                    t.primary_key %i[location device quantity regime
                                     influence mode]
                end

                def locations(t)
                    %i[location quantity].each { t.String it, null: false }
                    %i[reference exclude].each { t.String it }
                    %i[sigma drift].each { t.Float it }
                    t.Integer :max_age
                    t.String :deltas, text: true
                    t.primary_key %i[location quantity]
                end

                def tracks(t)
                    key(t)
                    %i[reference state].each { t.String it, null: false }
                    %i[constant plain].each { t.Float it }
                    floats(t, %i[delta variance cusum_up cusum_down])
                    t.Time :tracked_at, null: false
                    t.primary_key %i[location device quantity]
                end

                def key(t)
                    %i[location device quantity regime].each do |name|
                        t.String name, null: false
                    end
                end

                def widths(t)
                    floats(t, %i[p10 p90])
                    t.Integer :samples, null: false
                end

                def learned(t)
                    %i[learned_from learned_to learned_at].each do |name|
                        t.Time name, null: false
                    end
                end

                def floats(t, names)
                    names.each { t.Float it, null: false }
                end
            end
        end
    end
end
