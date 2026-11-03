# frozen_string_literal: true

require "json"

require "sequel"

require "sensorium"

require_relative "knowing"
require_relative "sequel/clock"
require_relative "sequel/column_names"
require_relative "sequel/location_rows"
require_relative "sequel/tracks"
require_relative "sequel/dynamics_rows"
require_relative "sequel/collocation_rows"
require_relative "sequel/transient_rows"
require_relative "sequel/forget"

module Sensorium
    module Store
        # In an SQL database, through Sequel: SQLite, MariaDB, PostgreSQL…
        # Seven tables, named by `tables`; with migrate: true they are
        # created when missing (Store::Sequel::Schema), else they must be
        # there already, as the caller made them, their columns named
        # as `columns` renames them ({ location: :zone }). Lists are kept
        # as A,B, an Offset's maps (switches, taus, series, states) as
        # JSON.
        class Sequel
            include Clock
            include ColumnNames
            include LocationRows
            include DynamicsRows
            include CollocationRows
            include TransientRows

            MAPS = %i[switches taus series states].freeze

            TABLES = { offsets: :sensor_offsets, shifts: :sensor_shifts,
                       locations: :sensor_locations,
                       tracks: :sensor_tracks,
                       dynamics: :sensor_dynamics,
                       collocations: :sensor_collocations,
                       transients: :sensor_transients }.freeze

            include Tracks
            include Forget
            include Knowing

            def initialize(db, tables: {}, columns: {}, migrate: true)
                @db      = db
                @tables  = TABLES.merge(tables)
                @columns = checked(columns)
                Schema.create(db, @tables, @columns) if migrate
            end

            def offsets(quantity)
                rows(:offsets, quantity, %i[location device])
                    .map { Offset.new(**offset(it)) }
            end

            def shifts(quantity)
                rows(:shifts, quantity, %i[location device influence mode])
                    .map { Shift.new(**it.slice(*Shift.members)) }
            end

            def learned(quantity)
                times = %i[learned_from learned_to learned_at]
                scope(:offsets, { quantity: })
                    .distinct.select_map([name_of(:regime),
                                          *times.map { time_column(it) }])
                    .map { utc_row(it) }.group_by(&:first)
                    .transform_values { latest(it) }
            end

            def keep(learned, from:, to:, at: Time.now)
                span = { learned_from: from.utc, learned_to: to.utc,
                         learned_at: at.utc }
                @db.transaction do
                    quantity = learned.quantity
                    drop(quantity, learned.gone(offsets(quantity)))
                    insert(learned, span)
                end
            end

            def locations(quantity)
                rows(:locations, quantity, %i[location])
                    .to_h { [it[:location], location(it)] }
            end

            def set_location(quantity, name, settings)
                key = { location: name, quantity: }
                row = scope(:locations, key).first || key
                row = row.merge(columns(settings))
                @db.transaction do
                    scope(:locations, key).delete
                    put(:locations, [row])
                end
            end

            private

            # The span of the latest learning of a regime's rows.
            def latest(rows) = rows.map { it.drop(1) }.max_by(&:last)

            # The offsets and shifts of those [location, device, regime].
            def drop(quantity, keys)
                keys.each do |location, device, regime|
                    key = { quantity:, location:, device:, regime: }
                    %i[offsets shifts].each { scope(it, key).delete }
                end
            end

            def insert(learned, span)
                put(:offsets, learned.offsets.map { row(it).merge(span) })
                put(:shifts, learned.shifts.map(&:to_h))
            end

            def offset(row)
                row.slice(*Offset.members)
                   .merge(MAPS.to_h { [it, JSON.parse(row[it] || "{}")] })
            end

            def row(offset)
                values = offset.to_h
                values.merge(MAPS.to_h { [it, JSON.generate(values[it])] })
            end
        end
    end
end

require_relative "sequel/schema"
