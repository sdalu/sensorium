# frozen_string_literal: true

module Sensorium
    # Where what a learning found is kept, and the locations' settings.
    # A store answers, each for one quantity (its name):
    #   offsets(quantity)                  [Offset]
    #   shifts(quantity)                   [Shift]
    #   learned(quantity)                  { regime => [from, to, at] } of
    #                                      the latest learning kept in it
    #   keep(learned, from:, to:, at:)     replaces what Learned#gone
    #                                      says
    #   locations(quantity)                { name => Location }, those set
    #   set_location(quantity, name, settings)
    #                                      settings: { key => value, nil
    #                                      back to the default }
    #   tracks(quantity)                   { [location, device] => Track }
    #   keep_tracks(quantity, tracks)      replaces them all
    #   dynamics(quantity)                 [Dynamics::Model]
    #   keep_dynamics(quantity, models)    replaces those of the same
    #                                      location and regime
    module Store
        # In memory: for tests, and for a learning used at once.
        class Memory
            def initialize
                @offsets   = []
                @shifts    = []
                @spans     = {}
                @locations = {}
                @tracks    = {}
                @dynamics  = []
            end

            def offsets(quantity) = @offsets.select { it.quantity == quantity }
            def shifts(quantity)  = @shifts.select { it.quantity == quantity }

            def learned(quantity)
                offsets(quantity).map { [it.regime, @spans[key(it)]] }
                                 .group_by(&:first)
                                 .transform_values { latest(it) }
            end

            def keep(learned, from:, to:, at: Time.now)
                drop = dropped(learned)
                @offsets = @offsets.reject(&drop) + learned.offsets
                @shifts  = @shifts.reject(&drop) + learned.shifts
                learned.offsets.each { @spans[key(it)] = [from, to, at] }
            end

            def locations(quantity)
                @locations.filter_map do |(q, name), location|
                    [name, location] if q == quantity
                end.to_h
            end

            def set_location(quantity, name, settings)
                now = @locations.fetch([quantity, name]) do
                    Location.default(name)
                end
                @locations[[quantity, name]] =
                    Location.new(**now.to_h, **settings)
            end

            def tracks(quantity) = @tracks.fetch(quantity, {})

            def keep_tracks(quantity, tracks)
                @tracks[quantity] = tracks.dup.freeze
            end

            def dynamics(quantity)
                @dynamics.select { it.quantity == quantity }
            end

            def keep_dynamics(quantity, models)
                keys = models.to_set { [it.location, it.regime] }
                @dynamics = @dynamics.reject do |model|
                    model.quantity == quantity &&
                        keys.include?([model.location, model.regime])
                end + models
            end

            private

            def key(row) = [row.quantity, *Learned.key(row)]

            # Whether a kept offset or shift gives way to the learning.
            def dropped(learned)
                gone = learned.gone(offsets(learned.quantity))
                lambda do |row|
                    row.quantity == learned.quantity &&
                        gone.include?(Learned.key(row))
                end
            end

            # The span of the latest learning: [[regime, [from, to, at]]].
            def latest(rows) = rows.map(&:last).max_by(&:last)
        end
    end
end
