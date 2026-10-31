# frozen_string_literal: true

module Sensorium
    class Snapshot
        # What Snapshot.from asks the source.
        module Gather
            module_function

            def readings(source, setup, at, window)
                quantity = setup.quantity.name
                found = source.readings(quantity, at - window, at, nil)
                return found unless source.respond_to?(:externals)
                found + source.externals(quantity, at - window, at)
            end

            # { name => Set of locations } of the Switches on at `at`.
            def switches(source, setup, at)
                setup.switches.to_h do |switch|
                    [switch.name, events(source, switch, at)
                        .select { switch.on?(it.last) }
                        .to_set { Influence.where(switch, it[1]) }]
                end
            end

            # { location => { name => value } }: each Mode's latest value
            # within its hold.
            def modes(source, setup, at)
                setup.modes.each_with_object({}) do |mode, all|
                    events(source, mode, at).sort_by(&:first)
                                            .each do |_, location, raw|
                        value = mode.value(raw) or next
                        where = Influence.where(mode, location)
                        (all[where] ||= {})[mode.name] = value
                    end
                end
            end

            # { name => { location => value } }: each Series' latest
            # value within its hold.
            def feeds(source, setup, at)
                setup.levels.to_h do |level|
                    latest = events(source, level, at).sort_by(&:first)
                    [level.name, latest.to_h do |_, location, value|
                        [Influence.where(level, location), value.to_f]
                    end]
                end
            end

            # { name => { location => Set of bins on } } of the filtered
            # Switches, over five of their longest time constant (and
            # their hold) before at.
            def pulses(source, setup, at)
                setup.switches.reject { it.taus.empty? }.to_h do |switch|
                    [switch.name, pulse(source, switch, setup.series, at)]
                end
            end

            def pulse(source, switch, series, at)
                on = Timeline.events(source, switch.name, at - span(switch),
                                     at)
                on.select { switch.on?(it.last) }
                  .group_by { Influence.where(switch, it[1]) }
                  .transform_values { spans(series, it, switch.hold) }
            end

            # Five of the Switch's longest time constant, and its hold.
            def span(switch) = (5 * switch.taus.max) + switch.hold

            def spans(series, events, hold)
                series.spans(events.map(&:first), hold)
            end

            def events(source, influence, at)
                Timeline.events(source, influence.name,
                                at - influence.hold, at)
            end
        end
    end
end
