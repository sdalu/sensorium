# frozen_string_literal: true

module Sensorium
    # The site at a moment, as the fusion needs it: each sensor's latest
    # reading, as it reads (latest: { [location, device] => Reading },
    # externals under the location nil), the Switches on (switches:
    # { name => locations, nil for the whole site }), the Modes holding
    # (modes: { location or nil => { name => value } }) and the readings
    # before the latest (history: { [location, device] => [Reading] },
    # oldest first).
    Snapshot = Data.define(:at, :latest, :switches, :modes, :history) do
        def initialize(switches: {}, modes: {}, history: {}, **) = super

        # From a source as the Learner's, the readings of the `window`
        # seconds before at.
        def self.from(source, setup, at:, window: 3 * 3600)
            gather = Snapshot::Gather
            readings = gather.readings(source, setup, at, window)
            new(at:, latest: latest(readings), history: history(readings),
                switches: gather.switches(source, setup, at),
                modes: gather.modes(source, setup, at))
        end

        def self.history(readings)
            readings.group_by { [it.location, it.device] }
                    .transform_values { it.sort_by(&:time) }
        end

        def self.latest(readings)
            readings.group_by { [it.location, it.device] }
                    .transform_values { it.max_by(&:time) }
        end

        # The devices of a location with a reading.
        def devices(location)
            latest.keys.filter_map do |where, device|
                device if where == location
            end
        end

        # The locations with a reading, externals aside.
        def locations = latest.keys.filter_map(&:first).uniq

        # A neighbour's reading by the Learner's name for it, whatever
        # "/" its location or device holds.
        def neighbour(name)
            latest.find do |key, _|
                Learner::Neighbours.name_of(*key) == name
            end&.last
        end

        # The names of the Switches on where the location is.
        def on(location)
            switches.filter_map do |name, where|
                name if where.include?(nil) || where.include?(location)
            end
        end

        # [[name, value]] of the Modes holding where the location is.
        def holding(location)
            modes.fetch(nil, {}).merge(modes.fetch(location, {})).to_a
        end

        def age(reading) = at - reading.time
    end
end

require_relative "snapshot/gather"
