# frozen_string_literal: true

module Sensorium
    # The influences over a span of history, by bin, from the source's
    # events: when each Switch was on, and when each Mode held which
    # value. A site-wide influence is kept under the location nil.
    class Timeline
        def initialize(setup, source, from, to)
            @series = setup.series
            events = ->(name) { Timeline.events(source, name, from, to) }
            @on = setup.switches.to_h do |switch|
                [switch.name, on(switch, events.call(switch.name))]
            end
            @modes = setup.modes.to_h do |mode|
                [mode.name, held(mode, events.call(mode.name))]
            end
        end

        # The source's events, none when it tells none.
        def self.events(source, name, from, to)
            return [] unless source.respond_to?(:events)
            source.events(name, from, to)
        end

        # { name => bins the Switch was on } where the location is.
        def switches(location)
            @on.transform_values do |by|
                by.fetch(nil, Set.new) | by.fetch(location, Set.new)
            end
        end

        # Whether a Mode held, or held within its hold, at a bin.
        def near?(location, bin)
            @modes.each_value.any? do |held|
                [nil, location].any? { held[:near][it]&.include?(bin) }
            end
        end

        # [[influence, value]] of the Modes holding at a bin.
        def modes(location, bin)
            @modes.filter_map do |name, held|
                value = held[:at][[nil, bin]] || held[:at][[location, bin]]
                [name, value] if value
            end
        end

        private

        def on(switch, events)
            events.select { switch.on?(it.last) }
                  .group_by { Influence.where(switch, it[1]) }
                  .transform_values do |list|
                      @series.spans(list.map(&:first), switch.hold)
                  end
        end

        def held(mode, events)
            events = events.filter_map do |time, location, raw|
                value = mode.value(raw) or next
                [time, Influence.where(mode, location), value]
            end
            { near: events.group_by { it[1] }.transform_values do |list|
                @series.spans(list.map(&:first), mode.hold)
            end,
              at: events.to_h do |time, location, value|
                  [[location, @series.bin(time)], value]
              end }
        end
    end
end
