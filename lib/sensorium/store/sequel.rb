# frozen_string_literal: true

require "json"

require "sequel"

require "sensorium"

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
        # there already, as the caller made them. Lists are kept as A,B,
        # an Offset's maps (switches, taus, series, states) as JSON.
        class Sequel
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

            def initialize(db, tables: {}, migrate: true)
                @db     = db
                @tables = TABLES.merge(tables)
                Schema.create(db, @tables) if migrate
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
                table(:offsets).where(quantity:).distinct
                               .select_map(%i[regime learned_from learned_to
                                              learned_at])
                               .group_by(&:first)
                               .transform_values { latest(it) }
            end

            def keep(learned, from:, to:, at: Time.now)
                span = { learned_from: from, learned_to: to, learned_at: at }
                @db.transaction do
                    quantity = learned.quantity
                    drop(quantity, learned.gone(offsets(quantity)))
                    insert(learned, span)
                end
            end

            def locations(quantity)
                table(:locations).where(quantity:).order(:location).all
                                 .to_h { [it[:location], location(it)] }
            end

            def set_location(quantity, name, settings)
                key = { location: name, quantity: }
                row = table(:locations).where(key).first || key
                row = row.merge(columns(settings))
                @db.transaction do
                    table(:locations).where(key).delete
                    table(:locations).insert(row)
                end
            end

            private

            def table(name) = @db[@tables.fetch(name)]

            # The span of the latest learning of a regime's rows.
            def latest(rows) = rows.map { it.drop(1) }.max_by(&:last)

            # The offsets and shifts of those [location, device, regime].
            def drop(quantity, keys)
                keys.each do |location, device, regime|
                    key = { quantity:, location:, device:, regime: }
                    %i[offsets shifts].each { table(it).where(key).delete }
                end
            end

            def insert(learned, span)
                table(:offsets).multi_insert(
                    learned.offsets.map { row(it).merge(span) }
                )
                table(:shifts).multi_insert(learned.shifts.map(&:to_h))
            end

            # A Location's settings as its row's columns: lists as A,B,
            # deltas as JSON.
            def columns(settings)
                settings.to_h do |key, value|
                    [key == :references ? :reference : key, column(value)]
                end
            end

            def column(value)
                case value
                when Array then value.join(",")
                when Hash then JSON.generate(value)
                else value
                end
            end

            def rows(name, quantity, order)
                table(name).where(quantity:).order(*order).all
            end

            def offset(row)
                row.slice(*Offset.members)
                   .merge(MAPS.to_h { [it, JSON.parse(row[it] || "{}")] })
            end

            def row(offset)
                values = offset.to_h
                values.merge(MAPS.to_h { [it, JSON.generate(values[it])] })
            end

            def location(row)
                Location.new(name: row[:location],
                             references: row[:reference]&.split(","),
                             exclude: row[:exclude]&.split(","),
                             deltas: JSON.parse(row[:deltas] || "{}"),
                             **row.slice(:sigma, :drift, :max_age))
            end
        end
    end
end

require_relative "sequel/schema"
