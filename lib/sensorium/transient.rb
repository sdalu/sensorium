# frozen_string_literal: true

module Sensorium
    # Sudden changes no learned term explains (a window opened, a
    # shower, the sun on a sensor), told apart by how far a sensor's
    # change over a window strays from the changes it usually makes.
    # Each sensor's scales are learned (learn), per regime and window;
    # the Detector finds the events of a Snapshot by them; a Learner
    # given an Influence::Transient leaves the bins they cover out of
    # the offsets.
    module Transient
        # σ from a median absolute deviation, as for a normal
        # distribution.
        MAD = 1.4826

        # How a sensor's change over a window spreads: σ, 1.4826 × the
        # median absolute deviation of the changes, and their median.
        Scale = Data.define(:sigma, :median) do
            # How far a change strays, in σ.
            def z(change) = (change - median).fdiv(sigma)
        end

        # A sensor's scales in one regime, { window => Scale }: own, of
        # its own change; relative, of the change of its gap to its
        # location's reference (none for a reference itself).
        Profile = Data.define(:location, :device, :quantity, :regime, :own,
                              :relative)

        # A change seen at `at`: direction :fall or :rise, z in σ of the
        # sensor's own scale over `window` seconds.
        Event = Data.define(:location, :device, :direction, :z, :window,
                            :at)

        module_function

        # [Profile] of every sensor of the source over a span, from a
        # source as the Learner's; locations: { name => Location }, those
        # set, for the references.
        def learn(source, setup, from:, to:, locations: {})
            sensors = source.sensors(setup.quantity.name)
            references = Learner::References.new(sensors, locations, setup)
            Changes.new(setup, data(source, setup, from, to,
                                    names(sensors, locations)),
                        references.all, Timeline.new(setup, source, from, to))
                   .profiles
        end

        # { [location, device] => { bin => value } }, in the transform's
        # space.
        def data(source, setup, from, to, names)
            readings = source.readings(setup.quantity.name, from, to, names)
            setup.series.of(setup.quantity.inward(readings))
        end

        # The devices read: the sensors, and the references set.
        def names(sensors, locations)
            (sensors.map(&:name) +
             locations.values.flat_map(&:references)).uniq
        end

        # The Scale of changes, nil when fewer than `least`.
        def scale(changes, least)
            return if changes.empty? || changes.size < least
            median = Stats.median(changes)
            deviation = Stats.median(changes.map { (it - median).abs })
            Scale.new(sigma: MAD * deviation, median:)
        end
    end
end

require_relative "transient/changes"
require_relative "transient/detector"
