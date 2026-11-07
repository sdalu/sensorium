# frozen_string_literal: true

module Sensorium
    # Readings put in bins of `width` seconds (a bin is its start, in
    # seconds since the epoch), each the mean of the readings in it.
    class Series
        # The least exposure that is not none.
        NONE = 1e-9

        attr_reader :width

        def initialize(width) = @width = width

        def bin(time) = time.to_i / @width * @width

        # { [location, device] => { bin => value } }: each bin the mean of
        # its readings, or their sum (total: true) for a quantity that
        # adds up over time (energy: the kWh a meter reports each hour).
        def of(readings, total: false)
            readings.group_by { [it.location, it.device] }
                    .transform_values { total ? sums(it) : means(it) }
        end

        def means(readings)
            readings.group_by { bin(it.time) }.transform_values do |list|
                list.sum { it.value.to_f } / list.size
            end
        end

        def sums(readings)
            readings.group_by { bin(it.time) }.transform_values do |list|
                list.sum { it.value.to_f }
            end
        end

        # { bin => mean } of values told as [[time, value]], each
        # holding from its time until the next one's, `hold` seconds at
        # most, the mean over each bin weighted by how long each held in
        # it: where a level told only when it changes stood. A bin
        # nothing held in is absent; one held in only in part is the
        # mean over that part.
        def weighted(told, hold)
            totals = Hash.new { |all, bin| all[bin] = [0.0, 0] }
            holds(told, hold).each { held(*it, totals) }
            totals.transform_values { |sum, seconds| sum / seconds }
        end

        # [[from, to, value]] of each value told, in seconds: until the
        # next, `hold` at most.
        def holds(told, hold)
            sorted = told.sort_by(&:first)
            sorted.zip(sorted.drop(1)).map do |(time, value), after|
                start = time.to_i
                [start, [start + hold, after&.first&.to_i].compact.min,
                 value.to_f]
            end
        end

        # value × the seconds it held, and those seconds, added to each
        # bin from..to spans.
        def held(from, to, value, totals)
            at = from
            while at < to
                stop = [bin(at) + @width, to].min
                total = totals[bin(at)]
                total[0] += value * (stop - at)
                total[1] += stop - at
                at = stop
            end
        end

        # { bin => value } of several series added bin by bin, over the
        # bins any of them has (a house's meters into one total).
        def added(all)
            all.each_with_object(Hash.new(0.0)) do |series, total|
                series.each { |bin, value| total[bin] += value }
            end.to_h
        end

        # The series with each value carried forward to the bins that
        # follow it, up to `seconds` after (a sensor that reports every
        # 10 to 30 minutes still has a value in every bin).
        def carried(series, seconds)
            series.keys.sort.each_with_object({}) do |at, result|
                (0..seconds).step(@width) { result[at + it] = series[at] }
            end
        end

        # { bin => how fast the series moves, per hour }: the central
        # difference over one bin each side, where both are known.
        def rates(series)
            series.filter_map do |bin, _|
                after = series[bin + @width]
                before = series[bin - @width]
                next unless after && before
                [bin, (after - before) * 3600.0 / (2 * @width)]
            end.to_h
        end

        # { bin => exposure } from the bin of first to that of last: a
        # first-order filter, of time constant tau seconds, of being in
        # `on` (a Set of bins), from 0. Below NONE it is 0: a tail that
        # never quite reaches it would let a slope blow up.
        def filtered(on, first, last, tau)
            keep = Math.exp(-@width.fdiv(tau))
            x = 0.0
            (bin(first)..bin(last)).step(@width).to_h do |at|
                x = (x * keep) + (on.include?(at) ? 1 - keep : 0.0)
                x = 0.0 if x < NONE
                [at, x]
            end
        end

        # The mean of the series, each carried `seconds`.
        def reference(all, seconds)
            mean(all.map { carried(it, seconds) })
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

        # The bins at, and up to `seconds` after, each of the times: the
        # hold counts from the time, not from its bin.
        def spans(times, seconds)
            times.each_with_object(Set.new) do |time, bins|
                (bin(time)..bin(time.to_i + seconds))
                    .step(@width) { bins << it }
            end
        end
    end
end
