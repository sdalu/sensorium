# frozen_string_literal: true

module Sensorium
    class Fit
        # The linear terms, each fitted on what a model left, over the
        # bins its regressors cover (a share setup.covers of the model's
        # at least).
        module Linear
            module_function

            def gain(model, levels, setup)
                fit(model, [levels], setup) do |base, (slope)|
                    { constant: model.constant + base, gain: slope }
                end
            end

            def neighbour(model, name, gaps, setup)
                fit(model, [gaps], setup) do |base, (slope)|
                    { constant: model.constant + base, neighbour: name,
                      coefficient: slope }
                end
            end

            def both(model, levels, name, gaps, setup)
                fit(model, [levels, gaps], setup) do |base, (gain, slope)|
                    { constant: model.constant + base, gain:,
                      neighbour: name, coefficient: slope }
                end
            end

            # xs: one or two { bin => x }. Yields the intercept and the
            # slopes, for the model's changes.
            def fit(model, xs, setup)
                bins = covered(model, xs, setup) or return
                ys = bins.map { model.residuals[it] }
                solved = solve(bins, xs, ys) or return
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

            def solve(bins, xs, ys)
                columns = xs.map { |x| bins.map { x[it] } }
                how = columns.one? ? :line : :plane
                Stats.public_send(how, *columns, ys)
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
