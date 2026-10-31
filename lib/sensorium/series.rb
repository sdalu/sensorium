# frozen_string_literal: true

module Sensorium
    # Readings put in bins of `width` seconds (a bin is its start, in
    # seconds since the epoch), each the mean of the readings in it.
    class Series
        attr_reader :width

        def initialize(width) = @width = width

        def bin(time) = time.to_i / @width * @width

        # { [location, device] => { bin => value } }.
        def of(readings)
            readings.group_by { [it.location, it.device] }
                    .transform_values { means(it) }
        end

        def means(readings)
            readings.group_by { bin(it.time) }.transform_values do |list|
                list.sum { it.value.to_f } / list.size
            end
        end

        # The series with each value carried forward to the bins that
        # follow it, up to `seconds` after (a sensor that reports every
        # 10 to 30 minutes still has a value in every bin).
        def carried(series, seconds)
            series.keys.sort.each_with_object({}) do |at, result|
                (0..seconds).step(@width) { result[at + it] = series[at] }
            end
        end

        # { bin => mean } over the bins every series has; the one series
        # itself when alone.
        def mean(all)
            return all.first if all.one?
            all.first.keys.filter_map do |bin|
                values = all.map { it[bin] }
                [bin, values.sum / values.size] unless values.include?(nil)
            end.to_h
        end

        # The bins at, and up to `seconds` after, each of the times.
        def spans(times, seconds)
            times.each_with_object(Set.new) do |time, bins|
                (0..seconds).step(@width) { bins << (bin(time) + it) }
            end
        end
    end
end
