# frozen_string_literal: true

module Sensorium
    module Dynamics
        # A location's reference predicted some hours ahead: from its
        # value at a bin, by the model's change over the hours, from the
        # inputs at the bin predicted (the outside, the Switches on).
        class Forecast
            # reference, outside: { bin => value } (outside nil: none);
            # on: { name => bins on }; near: answers call(bin) with
            # whether a Mode held at the bin, or within its hold (nil:
            # never).
            def initialize(reference, outside, on, near = nil)
                @reference = reference
                @outside   = outside
                @on        = on
                @near      = near
            end

            # [[model's error, holding's error]] from each of the bins
            # where the reference is known then and `hours` after, the
            # hours rounded to whole bins of the model's, one at least,
            # and no Mode held over the span: a forecast across one
            # errs by the Mode's doing, not the model's.
            def errors(model, bins, hours)
                ahead = ahead(model, hours)
                hours = ahead / 3600.0
                bins.filter_map do |bin|
                    next if held?(bin, bin + ahead, model.bin)
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

            # The mean square error per hour of the horizon: the mean
            # square over the horizon in whole bins, over its hours.
            def per_hour(model, bins, hours)
                square = mean_square(model, bins, hours) or return
                square * 3600.0 / ahead(model, hours)
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

            # Whether a Mode held, or held within its hold, at any bin
            # from `from` to `to`.
            def held?(from, to, width)
                @near && (from..to).step(width).any? { @near.call(it) }
            end

            # The seconds of the whole bins nearest `hours`, one at least.
            def ahead(model, hours)
                [(hours * 3600.0 / model.bin).round, 1].max * model.bin
            end

            def change(model, from, target, hours)
                on = @on.filter_map do |name, bins|
                    name if bins.include?(target)
                end
                model.change(from, @outside&.[](target), on, hours)
            end
        end
    end
end
