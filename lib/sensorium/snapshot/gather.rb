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

            def events(source, influence, at)
                Timeline.events(source, influence.name,
                                at - influence.hold, at)
            end
        end
    end
end
