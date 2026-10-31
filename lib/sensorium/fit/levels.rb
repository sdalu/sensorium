# frozen_string_literal: true

module Sensorium
    class Fit
        # The spreads of what a model leaves per level of its Series
        # (Offset#states): over the bins each was above its median over
        # the fit ("NAME:high") and over those it was not ("NAME:low"),
        # each [p10, p90, the median], kept when it has min_part bins at
        # least.
        module Levels
            module_function

            # series: { name => { bin => value } }.
            def of(model, series, min_part)
                model.series.keys.each_with_object({}) do |name, found|
                    values = series.fetch(name, {})
                    found.merge!(levels(model.residuals, values, name,
                                        min_part))
                end
            end

            # { "NAME:high" => [p10, p90, median], "NAME:low" => ... }.
            def levels(residuals, values, name, min_part)
                bins = residuals.keys.select { values.key?(it) }
                return {} if bins.empty?
                median = median(values.values_at(*bins))
                high, low = bins.partition { values[it] > median }
                { "#{name}:high" => high, "#{name}:low" => low }
                    .filter_map do |key, part|
                        found = States.widths(residuals.values_at(*part),
                                              min_part) or next
                        [key, [*found, median]]
                    end.to_h
            end

            # Four significant digits, as a Series' coefficient is kept.
            def median(values) = Learned.significant(Stats.median(values))
        end
    end
end
