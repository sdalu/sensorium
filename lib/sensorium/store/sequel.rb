# frozen_string_literal: true

require "json"

require "sequel"

require "sensorium"

module Sensorium
    module Store
        # In an SQL database, through Sequel: SQLite, MariaDB, PostgreSQL…
        # Three tables, named by `tables`; with migrate: true they are
        # created when missing (Store::Sequel::Schema), else they must be
        # there already, as the caller made them. Lists are kept as A,B,
        # an Offset's switches as JSON.
        class Sequel
            TABLES = { offsets: :sensor_offsets, shifts: :sensor_shifts,
                       locations: :sensor_locations }.freeze

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
                               .to_h { |regime, *span| [regime, span] }
            end

            def keep(learned, from:, to:, at: Time.now)
                span = { learned_from: from, learned_to: to, learned_at: at }
                @db.transaction do
                    %i[offsets shifts].each do |name|
                        table(name).where(quantity: learned.quantity,
                                          regime: learned.regimes).delete
                    end
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

            def insert(learned, span)
                table(:offsets).multi_insert(
                    learned.offsets.map { row(it).merge(span) }
                )
                table(:shifts).multi_insert(learned.shifts.map(&:to_h))
            end

            # A Location's settings as its row's columns.
            def columns(settings)
                settings.to_h do |key, value|
                    [key == :references ? :reference : key,
                     value.is_a?(Array) ? value.join(",") : value]
                end
            end

            def rows(name, quantity, order)
                table(name).where(quantity:).order(*order).all
            end

            def offset(row)
                row.slice(*Offset.members)
                   .merge(switches: JSON.parse(row[:switches] || "{}"))
            end

            def row(offset)
                offset.to_h.merge(switches: JSON.generate(offset.switches))
            end

            def location(row)
                Location.new(name: row[:location],
                             references: row[:reference]&.split(","),
                             exclude: row[:exclude]&.split(","),
                             **row.slice(:sigma, :drift, :max_age))
            end
        end
    end
end

require_relative "sequel/schema"
