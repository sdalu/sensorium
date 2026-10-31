# frozen_string_literal: true

module Sensorium
    class Fit
        # Every term a greedy model kept, refitted together once: one
        # least-squares regression of the diffs on an intercept and each
        # kept term's regressor (a Switch's on-state, or its exposure at
        # its τ when filtered; a Series' value; the reference's level for
        # the gain; the gap to the neighbour; the reference's rate), over
        # the bins all of them cover. The refit is kept when it leaves a
        # spread (p10..p90) no wider than the greedy model's over the
        # same bins, and |1 + gain + coefficient| at setup.scale_floor at
        # least; else the greedy model. A model with fewer than two
        # terms is left as it is: there is nothing to fit together, and a
        # lone gain keeps its Deming line.
        class Joint
            def initialize(diffs, setup, levels, terms)
                @diffs  = diffs
                @setup  = setup
                @levels = levels
                @terms  = terms
            end

            # The refit model, or the greedy one.
            def of(model)
                columns = columns(model)
                return model if columns.size < 2
                bins = covered(model, columns)
                tried = solved(model, columns, bins) or return model
                kept?(model, tried, bins) ? tried : model
            end

            private

            # [[member, name, { bin => x }]] of the kept terms, the
            # Switches in the model's order.
            def columns(model)
                model.switches.keys.map { switch(model, it) } +
                    model.series.keys.map do |name|
                        [:series, name, @terms.series[name]]
                    end + linear(model)
            end

            def switch(model, name)
                tau = model.taus[name]
                return [:switches, name, @terms.filtered[name][tau]] if tau
                [:switches, name, on_state(@terms.switches[name])]
            end

            # { bin => 1 while on, else 0 } over the diffs' bins.
            def on_state(on)
                @diffs.keys.to_h { [it, on.include?(it) ? 1.0 : 0.0] }
            end

            def linear(model)
                gap = @terms.candidates[model.neighbour]
                [([:gain, nil, @levels] if model.gain),
                 ([:coefficient, nil, gap] if model.neighbour),
                 ([:rate, nil, @terms.rates] if model.rate)].compact
            end

            # The model's bins every regressor has.
            def covered(model, columns)
                model.residuals.keys.select do |bin|
                    columns.all? { |(_, _, x)| x.key?(bin) }
                end
            end

            # The model refitted over the bins, nil when the columns do
            # not vary apart.
            def solved(model, columns, bins)
                xs = columns.map { |(_, _, x)| bins.map { x[it] } }
                ys = bins.map { @diffs[it] }
                found = Stats.least_squares(xs, ys) or return
                base, *slopes = found
                model.with(constant: base, **members(columns, slopes),
                           residuals: left(bins, xs, ys, base, slopes))
            end

            # The model's members from the slopes.
            def members(columns, slopes)
                found = { switches: {}, series: {} }
                columns.zip(slopes) do |(member, name, _), slope|
                    found[member] = slope unless name
                    found[member] = found[member].merge(name => slope) if name
                end
                found
            end

            def left(bins, xs, ys, base, slopes)
                bins.each_with_index.to_h do |bin, i|
                    [bin, ys[i] - base - xs.zip(slopes).sum { |x, b| b * x[i] }]
                end
            end

            def kept?(model, tried, bins)
                before = Stats.spread(model.residuals.values_at(*bins))
                scale = 1 + (tried.gain || 0.0) + (tried.coefficient || 0.0)
                scale.abs >= @setup.scale_floor && tried.spread <= before
            end
        end
    end
end
