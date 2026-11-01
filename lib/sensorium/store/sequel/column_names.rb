# frozen_string_literal: true

module Sensorium
    module Store
        class Sequel
            # The caller's names for the store's columns (columns: {
            # location: :zone }), the same in every table: the rows read
            # are renamed back by their dataset's row proc, the keys
            # written and filtered on renamed out.
            module ColumnNames
                private

                def name_of(column) = @columns.fetch(column, column)
                def named(hash) = hash.transform_keys { name_of(it) }

                def table(name)
                    set = @db[@tables.fetch(name)]
                    return set if @columns.empty?
                    back = @columns.invert
                    set.with_row_proc(lambda do |row|
                        row.transform_keys { back.fetch(it, it) }
                    end)
                end

                # The rows of a table matching key ({ column => value }).
                def scope(name, key) = table(name).where(named(key))

                def put(name, rows)
                    table(name).multi_insert(rows.map { named(it) })
                end

                # The rows of a quantity, ordered by those columns.
                def rows(name, quantity, order)
                    scope(name, { quantity: })
                        .order(*order.map { name_of(it) }).all
                end

                # The columns given, refused when one is not a column of
                # the store's or two would share a name.
                def checked(columns)
                    unknown = columns.keys - Schema::Names.all
                    if unknown.any?
                        raise ArgumentError,
                              "no such column: #{unknown.join(", ")}"
                    end
                    names = Schema::Names.all.map { columns.fetch(it, it) }
                    return columns if names.uniq.size == names.size
                    raise ArgumentError, "two columns named alike"
                end
            end
        end
    end
end
