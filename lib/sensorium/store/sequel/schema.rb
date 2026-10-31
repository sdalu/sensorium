# frozen_string_literal: true

module Sensorium
    module Store
        class Sequel
            # The three tables, created when missing. A caller that keeps
            # its own schema (types, foreign keys) makes them alike and
            # opens the store with migrate: false.
            module Schema
                module_function

                def create(db, tables)
                    db.create_table?(tables.fetch(:offsets)) do
                        Schema.offsets(self)
                    end
                    db.create_table?(tables.fetch(:shifts)) do
                        Schema.shifts(self)
                    end
                    db.create_table?(tables.fetch(:locations)) do
                        Schema.locations(self)
                    end
                end

                def offsets(t)
                    key(t)
                    t.String :reference, null: false
                    t.Float :constant, null: false
                    t.String :switches, text: true
                    %i[gain coefficient].each { t.Float it }
                    t.String :neighbour
                    widths(t)
                    floats(t, %i[plain plain_p10 plain_p90])
                    learned(t)
                    t.primary_key %i[location device quantity regime]
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
                    t.primary_key %i[location quantity]
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
