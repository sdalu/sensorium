# frozen_string_literal: true

module Sensorium
    module Dynamics
        # A location's reference predicted some hours ahead, as the
        # Fusion ages a reading: from its value at a bin, by the model's
        # change over the hours, from the inputs at the bin predicted
        # (the outside, the Switches on).
        class Forecast
            # reference, outside: { bin => value } (outside nil: none);
            # on: { name => bins on }.
            def initialize(reference, outside, on)
                @reference = reference
                @outside   = outside
                @on        = on
            end

            # [[model's error, holding's error]] from each of the bins
            # where the reference is known then and `hours` after.
            def errors(model, bins, hours)
                ahead = (hours * 3600).round
                bins.filter_map do |bin|
                    from = @reference[bin] or next
                    truth = @reference[bin + ahead] or next
                    change = change(model, from, bin + ahead, hours) or next
                    [from + change - truth, from - truth]
                end
            end

            # The mean square of the model's errors; nil without any.
            def mean_square(model, bins, hours)
                found = errors(model, bins, hours)
                found.sum { it.first**2 } / found.size unless found.empty?
            end

            # [rms_model, rms_hold]; nil without any error.
            def rms(model, bins, hours)
                found = errors(model, bins, hours)
                return if found.empty?
                [0, 1].map do |i|
                    Math.sqrt(found.sum { it[i]**2 } / found.size)
                end
            end

            private

            def change(model, from, target, hours)
                on = @on.filter_map do |name, bins|
                    name if bins.include?(target)
                end
                model.change(from, @outside&.[](target), on, hours)
            end
        end
    end
end
