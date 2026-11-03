# frozen_string_literal: true

module Sensorium
    module Store
        class Sequel
            # Times read back as UTC, whatever Sequel or the database
            # makes of its own timezone. The write side gives Time#utc.
            # With a database timezone (the Database's, else Sequel's),
            # Sequel converts both ways and the Time read is the
            # instant. Without one, Sequel writes the UTC wall clock as
            # it is and parses it back as local time, then converts it
            # to the application's zone, so rebuilding from its local
            # wall-clock fields undoes exactly that, immune to the hour
            # Europe/Paris repeats every autumn.
            module Clock
                def wall_utc(time)
                    return time.getutc if @db.timezone
                    wall = time.getlocal
                    Time.utc(wall.year, wall.month, wall.day, wall.hour,
                             wall.min, wall.sec + wall.subsec)
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
