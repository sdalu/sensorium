# frozen_string_literal: true

module Sensorium
    class Learner
        # Each location's references: those its Location sets, else its
        # first sensor tagged with one of the places, in their order.
        class References
            # sensors: [Sensor]; locations: { name => Location }.
            def initialize(sensors, locations, setup)
                @sensors   = sensors.group_by(&:location)
                @locations = locations
                @places    = setup.places.map(&:to_s)
            end

            # { location => [device] }.
            def all
                placed = @sensors.filter_map do |location, list|
                    found = placed(list) and next [location, [found.name]]
                end.to_h
                set = @locations.transform_values(&:references)
                placed.merge(set.reject { |_, devices| devices.empty? })
            end

            # [location, device] of the sensors, and of the references set.
            def listed
                sensors = @sensors.values.flatten
                                  .to_set { [it.location, it.name] }
                sensors | @locations.flat_map do |name, location|
                    location.references.map { [name, it] }
                end
            end

            private

            def placed(list)
                @places.lazy.filter_map do |place|
                    list.find { it.tags.include?(place) }
                end.first
            end
        end
    end
end
