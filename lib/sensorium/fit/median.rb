# frozen_string_literal: true

module Sensorium
    class Fit
        # A hard Switch's term: the median while on over the median while
        # off, both of what a model left, each side setup.min_part bins
        # at least.
        module Median
            module_function

            def switch(model, name, on, setup)
                found = term(model.residuals, on, setup.min_part) or return
                base, term = found
                model.with(constant: model.constant + base,
                           switches: model.switches.merge(name => term),
                           residuals: switched(model.residuals, on, base,
                                               term))
            end

            # [the median while off, while on less it], nil when either
            # side has too few bins.
            def term(residuals, on, min_part)
                held, off = residuals.partition { |bin, _| on.include?(bin) }
                                     .map { |part| part.map(&:last) }
                return if [held, off].any? { it.size < min_part }
                base = Stats.median(off)
                [base, Stats.median(held) - base]
            end

            def switched(residuals, on, base, term)
                residuals.to_h do |bin, r|
                    [bin, r - base - (on.include?(bin) ? term : 0.0)]
                end
            end
        end
    end
end
