# frozen_string_literal: true

module Sensorium
    module Store
        class Sequel
            # Times read back as UTC, whatever Sequel or the database
            # makes of its own timezone. The write side gives Time#utc.
            # With a database timezone (the Database's, else Sequel's),
            # Sequel converts both ways and the Time read is the
            # instant. Without one, Sequel writes the UTC wall clock as
            # it is but would parse it back as local time, where the
            # hour Europe/Paris skips every spring does not exist: the
            # column is read as its text instead, parsed as UTC (an
            # offset in it honoured), immune to the hour repeated every
            # autumn too.
            module Clock
                # A time column as selected: without a database
                # timezone, its text, as name_text.
                def time_column(name)
                    column = name_of(name)
                    return column if @db.timezone
                    ::Sequel.cast(column, String).as(:"#{name}_text")
                end

                # The columns' texts, read beside the row's own.
                def texts(names)
                    @db.timezone ? [] : names.map { time_column(it) }
                end

                # The time name of a row read with its texts, as UTC.
                def utc_at(row, name)
                    utc(row.fetch(:"#{name}_text") { row[name] })
                end

                # A Time, or a time column's text, as UTC.
                def utc(time)
                    return time&.getutc unless time.is_a?(String)
                    DateTime.parse(time).to_time.getutc
                end

                # A [regime, learned_from, learned_to, learned_at] row
                # with its three times read as UTC.
                def utc_row(row)
                    [row.first, *row.drop(1).map { utc(it) }]
                end
            end
        end
    end
end
