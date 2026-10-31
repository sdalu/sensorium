# frozen_string_literal: true

module Sensorium
    class Fit
        # The linear terms, each fitted on what a model left, over the
        # bins its regressors cover (a share setup.covers of the model's
        # at least).
        module Linear
            module_function

            # The gain by Stats.gain: the reference read with an error of
            # its quantity's σ.
            def gain(model, levels, setup)
                quantity = setup.quantity
                solver = lambda do |(xs), ys|
                    Stats.gain(xs, ys, quantity.sigma, quantity.floor)
                end
                fit(model, [levels], setup, solver) do |base, (slope)|
                    { constant: model.constant + base, gain: slope }
                end
            end

            def neighbour(model, name, gaps, setup)
                fit(model, [gaps], setup) do |base, (slope)|
                    { constant: model.constant + base, neighbour: name,
                      coefficient: slope }
                end
            end

            def exposure(model, name, tau, exposures, setup)
                fit(model, [exposures], setup) do |base, (slope)|
                    { constant: model.constant + base,
                      switches: model.switches.merge(name => slope),
                      taus: model.taus.merge(name => tau) }
                end
            end

            def series(model, name, values, setup)
                fit(model, [values], setup) do |base, (slope)|
                    { constant: model.constant + base,
                      series: model.series.merge(name => slope) }
                end
            end

            def rate(model, rates, setup)
                fit(model, [rates], setup) do |base, (slope)|
                    { constant: model.constant + base, rate: slope }
                end
            end

            def both(model, levels, name, gaps, setup)
                fit(model, [levels, gaps], setup) do |base, (gain, slope)|
                    { constant: model.constant + base, gain:,
                      neighbour: name, coefficient: slope }
                end
            end

            # Least squares, on one column or two (the gain and the
            # neighbour together: see DESIGN.md).
            OLS = lambda do |columns, ys|
                Stats.public_send(columns.one? ? :line : :plane, *columns, ys)
            end

            # xs: one or two { bin => x }; solver: columns, ys →
            # [intercept, *slopes]. Yields the intercept and the slopes,
            # for the model's changes.
            def fit(model, xs, setup, solver = OLS)
                bins = covered(model, xs, setup) or return
                ys = bins.map { model.residuals[it] }
                columns = xs.map { |x| bins.map { x[it] } }
                solved = solver.call(columns, ys) or return
                base, *slopes = solved
                model.with(**yield(base, slopes),
                           residuals: left(bins, xs, ys, base, slopes))
            end

            # The model's bins every x has, nil when too few.
            def covered(model, xs, setup)
                bins = model.residuals.keys.select do |bin|
                    xs.all? { it.key?(bin) }
                end
                bins if bins.size >= setup.covers * model.residuals.size
            end

            def left(bins, xs, ys, base, slopes)
                bins.zip(ys).to_h do |bin, y|
                    terms = xs.zip(slopes).sum { |x, slope| slope * x[bin] }
                    [bin, y - base - terms]
                end
            end
        end
    end
end
