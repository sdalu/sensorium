# frozen_string_literal: true

module Sensorium
    module Store
        class Sequel
            # A Location's row, as Store::Sequel keeps it: lists as
            # A,B, deltas as JSON.
            module LocationRows
                private

                def columns(settings)
                    settings.to_h do |key, value|
                        [key == :references ? :reference : key, column(value)]
                    end
                end

                def column(value)
                    case value
                    when Array then value.join(",")
                    when Hash then JSON.generate(value)
                    else value
                    end
                end

                def location(row)
                    Location.new(name: row[:location],
                                 references: row[:reference]&.split(","),
                                 exclude: row[:exclude]&.split(","),
                                 deltas: JSON.parse(row[:deltas] || "{}"),
                                 **row.slice(:sigma, :drift, :max_age))
                end
            end
        end
    end
end
