# frozen_string_literal: true

module Sensorium
    # Where what a learning found is kept, and the locations' settings.
    # A store answers, each for one quantity (its name):
    #   offsets(quantity)                  [Offset]
    #   shifts(quantity)                   [Shift]
    #   learned(quantity)                  { regime => [from, to, at] }
    #   keep(learned, from:, to:, at:)     replaces the regimes covered
    #   locations(quantity)                { name => Location }, those set
    #   set_location(quantity, name, settings)
    #                                      settings: { key => value, nil
    #                                      back to the default }
    module Store
        # In memory: for tests, and for a learning used at once.
        class Memory
            def initialize
                @offsets   = []
                @shifts    = []
                @spans     = {}
                @locations = {}
            end

            def offsets(quantity) = @offsets.select { it.quantity == quantity }
            def shifts(quantity)  = @shifts.select { it.quantity == quantity }

            def learned(quantity)
                @spans.filter_map do |(q, regime), span|
                    [regime, span] if q == quantity
                end.to_h
            end

            def keep(learned, from:, to:, at: Time.now)
                gone = ->(row) { gone?(row, learned) }
                @offsets = @offsets.reject(&gone) + learned.offsets
                @shifts  = @shifts.reject(&gone) + learned.shifts
                learned.regimes.each do |regime|
                    @spans[[learned.quantity, regime]] = [from, to, at]
                end
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

            private

            def gone?(row, learned)
                row.quantity == learned.quantity &&
                    learned.regimes.include?(row.regime)
            end
        end
    end
end
