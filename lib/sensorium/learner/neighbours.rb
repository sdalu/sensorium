# frozen_string_literal: true

module Sensorium
    class Learner
        # What a location's sensors may be learned against beside their
        # reference: every other location's sensors, unless a Sensor
        # says it is no neighbour, and the externals (the location nil).
        # Named "LOCATION/DEVICE", an external by its device alone.
        class Neighbours
            # data: { [location, device] => { bin => value } }.
            def initialize(series, carry, sensors, data)
                @series = series
                @carry  = carry
                @not    = sensors.reject(&:neighbour)
                                 .to_set { [it.location, it.name] }
                @data   = data
            end

            def self.name_of(location, device)
                location ? "#{location}/#{device}" : device
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
