# frozen_string_literal: true

module Sensorium
    # The influences over a span of history, by bin, from the source's
    # events: when each Switch was on (and the exposure of the filtered
    # ones), when each Mode held which value, and each Series' level. A
    # site-wide influence is kept under the location nil.
    class Timeline
        def initialize(setup, source, from, to)
            @series = setup.series
            @span   = [from, to]
            @events = ->(name) { Timeline.events(source, name, from, to) }
            influences(setup)
        end

        # The source's events, none when it tells none.
        def self.events(source, name, from, to)
            return [] unless source.respond_to?(:events)
            source.events(name, from, to)
        end

        # { name => bins the Switch was on } where the location is, the
        # filtered ones aside.
        def switches(location)
            on_where(location).select { |name, _| @taus[name].empty? }
        end

        # { name => { tau => { bin => exposure } } } of the filtered
        # Switches where the location is.
        def exposures(location)
            on_where(location).filter_map do |name, on|
                next if @taus[name].empty?
                [name, @taus[name].to_h { [it, filtered(name, on, it)] }]
            end.to_h
        end

        # { name => { bin => value } } of the Series where the location
        # is.
        def series(location)
            @levels.transform_values do |by|
                by.fetch(nil, {}).merge(by.fetch(location, {}))
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

        def influences(setup)
            @taus   = setup.switches.to_h { [it.name, it.taus] }
            @on     = each_of(setup.switches) { on(*it) }
            @modes  = each_of(setup.modes) { held(*it) }
            @levels = each_of(setup.levels) { levels(*it) }
        end

        def on_where(location)
            @on.transform_values do |by|
                by.fetch(nil, Set.new) | by.fetch(location, Set.new)
            end
        end

        # Once per Switch, time constant and on-state: a site-wide
        # Switch's is the same everywhere.
        def filtered(name, on, tau)
            ((@filtered ||= {})[[name, tau]] ||= {})[on] ||=
                @series.filtered(on, *@span, tau)
        end

        def on(switch, events)
            events.select { switch.on?(it.last) }
                  .group_by { Influence.where(switch, it[1]) }
                  .transform_values do |list|
                      @series.spans(list.map(&:first), switch.hold)
                  end
        end

        # { name => what the block makes of the influence and its
        # events }.
        def each_of(influences)
            influences.to_h do |influence|
                [influence.name, yield([influence,
                                        @events.call(influence.name)])]
            end
        end

        # { where => { bin => mean } }, carried `hold`.
        def levels(level, events)
            events.group_by { Influence.where(level, it[1]) }
                  .transform_values do |list|
                      @series.carried(means(list), level.hold)
                  end
        end

        def means(events)
            events.group_by { @series.bin(it.first) }.transform_values do |list|
                list.sum { it.last.to_f } / list.size
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
