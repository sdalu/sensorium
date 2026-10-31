# frozen_string_literal: true

module Sensorium
    class Learner
        # What a location's sensors may be learned against beside their
        # reference: every other location's sensors, unless a Sensor
        # says it is no neighbour, and the externals (the location nil).
        # Named "LOCATION/DEVICE", an external by its device alone (see
        # name_of).
        class Neighbours
            # data: { [location, device] => { bin => value } }.
            def initialize(series, carry, sensors, data)
                @series = series
                @carry  = carry
                @not    = sensors.reject(&:neighbour)
                                 .to_set { [it.location, it.name] }
                @data   = data
            end

            # { [nil, device] => { bin => value } } of the source's
            # externals, in the transform's space; none when it tells
            # none.
            def self.externals(source, setup, from, to)
                return {} unless source.respond_to?(:externals)
                readings = source.externals(setup.quantity.name, from, to)
                setup.series.of(setup.quantity.inward(readings))
            end

            # "LOCATION/DEVICE", an external's DEVICE, each part's "%"
            # and "/" escaped (%25, %2F) so that no two names collide.
            def self.name_of(location, device)
                return escaped(device) unless location
                "#{escaped(location)}/#{escaped(device)}"
            end

            def self.escaped(part)
                part.to_s.gsub("%", "%25").gsub("/", "%2F")
            end

            # { name => { bin => reference - neighbour } } for a location,
            # its reference's carried series given.
            def gaps(location, reference)
                (@gaps ||= {})[location] ||= all.filter_map do |key, series|
                    next if key.first == location
                    [Neighbours.name_of(*key), reference.filter_map do |bin, r|
                        [bin, r - series[bin]] if series[bin]
                    end.to_h]
                end.to_h
            end

            private

            def all
                @all ||= @data.each_with_object({}) do |(key, series), all|
                    next if @not.include?(key)
                    all[key] = @series.carried(series, @carry)
                end
            end
        end
    end
end
