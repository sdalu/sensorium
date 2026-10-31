# frozen_string_literal: true

module Sensorium
    module Store
        class Sequel
            # Times read back as UTC, whatever Sequel or the database
            # makes of its own timezone: the write side always gives
            # UTC wall-clock (Time#utc), so rebuilding from the
            # column's wall-clock fields undoes exactly that, immune to
            # the hour Europe/Paris repeats every autumn.
            module Clock
                def wall_utc(time)
                    Time.utc(time.year, time.month, time.day, time.hour,
                             time.min, time.sec + time.subsec)
                end

                # A [regime, learned_from, learned_to, learned_at] row
                # with its three times read as UTC.
                def utc_row(row)
                    [row.first, *row.drop(1).map { wall_utc(it) }]
                end
            end
        end
    end
end
