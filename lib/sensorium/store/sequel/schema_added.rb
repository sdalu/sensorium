# frozen_string_literal: true

module Sensorium
    module Store
        class Sequel
            module Schema
                # The columns added since a table was first defined, each
                # nullable: a table made before them gets them (upgrade).
                ADDED = { offsets: { block_share: Float },
                          tracks: { block_sum: Float, block_noise: Float,
                                    block_count: Integer,
                                    block_at: Time } }.freeze

                module_function

                # The ADDED columns a table lacks, added; another process
                # adding them meanwhile is no failure.
                def upgrade(db, tables, columns)
                    ADDED.each do |name, added|
                        table = tables.fetch(name)
                        missing = missing(db, table, added, columns)
                        next if missing.empty?
                        add(db, table, missing, added, columns)
                    end
                end

                # The columns added, or found added since: re-raised
                # only if some are still missing once the schema is read
                # again.
                def add(db, table, missing, added, columns)
                    db.alter_table(table) do
                        missing.each { |col, type| add_column(col, type) }
                    end
                rescue ::Sequel::DatabaseError
                    db.schema(table, reload: true)
                    raise unless missing(db, table, added, columns).empty?
                end

                # { column => type } of those added a table lacks, named
                # as columns renames them.
                def missing(db, table, added, columns)
                    have = db.schema(table).map(&:first)
                    added.transform_keys { columns.fetch(it, it) }.except(*have)
                end
            end
        end
    end
end
