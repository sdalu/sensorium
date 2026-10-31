# frozen_string_literal: true

module Sensorium
    class Fit
        # The spreads of what a model leaves per state of its Switches
        # (Offset#states): over the bins each was on, and over those all
        # were off, each kept when it has min_part bins at least.
        module States
            module_function

            # on: { name => bins it was on }.
            def of(model, on, min_part)
                names = model.switches.keys
                return { states: {}, off_p10: nil, off_p90: nil } if
                    names.empty?
                off = widths(off(model.residuals, names.map { on[it] }),
                             min_part)
                { states: on_widths(model.residuals, names, on, min_part),
                  off_p10: off&.first, off_p90: off&.last }
            end

            def on_widths(residuals, names, on, min_part)
                names.filter_map do |name|
                    bins = on.fetch(name, Set.new)
                    found = widths(residuals.filter_map do |bin, r|
                        r if bins.include?(bin)
                    end, min_part) or next
                    [name, found]
                end.to_h
            end

            def off(residuals, sets)
                residuals.filter_map do |bin, r|
                    r unless sets.any? { it&.include?(bin) }
                end
            end

            # [p10, p90], rounded as an Offset's; nil under min_part.
            def widths(values, min_part)
                return if values.size < min_part
                Learned.widths(values).values_at(:p10, :p90)
            end
        end
    end
end
