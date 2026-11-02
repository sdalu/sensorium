# frozen_string_literal: true

module Sensorium
    class Fit
        # A Fit whose terms are chosen without the last tenth of the bins
        # (setup.min_part of them at least), each kept only when it also
        # leaves those no wider, within 5 % (HeldOut); the terms kept are
        # then fitted again on all the bins. With too few bins to hold
        # any out, the constant alone. What the terms narrow is measured
        # on the bins they were chosen on: the model's widths are to be
        # widened by as much as the bins held out confirm less
        # (confirmed).
        module Validated
            module_function

            SHARE = 0.1

            # The Fit, its model (chosen once: the greedy choice is the
            # costly part), and what its widths are to be widened by.
            Result = Data.define(:fit, :model, :inflation)

            # The Fit on all the diffs, its terms those chosen.
            def fit(diffs, setup, levels:, **terms)
                learn(diffs, setup, levels:, **terms).fit
            end

            # The Result on all the diffs.
            def learn(diffs, setup, levels:, **terms)
                sorted = diffs.sort
                held = held(sorted.size, setup)
                unless held
                    fit = plain(diffs, setup, levels, terms)
                    return Result.new(fit:, model: fit.model, inflation: 1.0)
                end
                parts = [sorted.first(sorted.size - held).to_h,
                         sorted.last(held).to_h]
                chosen(diffs, setup, levels, parts, terms)
            end

            # How many of the last bins are held out, nil when too few
            # would be left to fit on.
            def held(size, setup)
                held = [(size * SHARE).ceil, setup.min_part].max
                held if size - held >= setup.min_part
            end

            def plain(diffs, setup, levels, terms)
                Fit.new(diffs, setup.with(gain: false, rate: false),
                        levels:, held: terms.fetch(:held, {}))
            end

            # The Result of the terms chosen on the bins fitted, held out
            # on the others (parts: [fitted, out]), fitted again on all.
            def chosen(diffs, setup, levels, parts, terms)
                fitted, out = parts
                chosen = Fit.new(fitted, setup, levels:, **terms,
                                                held_out: out)
                model = chosen.model
                held_out = HeldOut.new(out, levels, chosen.terms)
                fit = again(diffs, setup, levels, chosen, model)
                held = held_out.narrowing(chosen.plain, model)
                refit = fit.model
                Result.new(fit:, model: refit,
                           inflation: confirmed(fit, refit, held))
            end

            # How much less the bins held out confirm the model narrows
            # the plain constant's spread (held: that narrowing) than the
            # refit on all the bins, whose widths are the ones widened,
            # claims: their ratio, at least 1; 1 when the refit kept no
            # term.
            def confirmed(fit, model, held)
                return 1.0 if model.equal?(fit.plain)
                before = fit.plain.residuals.values_at(*model.residuals.keys)
                claimed = model.spread / Stats.spread(before)
                return 1.0 unless claimed.positive? && claimed.finite?
                [held / claimed, 1.0].max
            end

            def again(diffs, setup, levels, chosen, model)
                Fit.new(diffs, setup.with(gain: setup.gain && !model.gain.nil?),
                        levels:, **kept(model, chosen.terms))
            end

            # The terms the model kept, the filtered Switches at their tau.
            def kept(model, terms)
                { series: terms.series.slice(*model.series.keys),
                  candidates: terms.candidates.slice(*model.neighbour),
                  rates: (terms.rates if model.rate), held: terms.held,
                  **switches(model, terms) }
            end

            def switches(model, terms)
                hard = model.switches.keys - model.taus.keys
                { switches: terms.switches.slice(*hard),
                  filtered: model.taus.to_h do |name, tau|
                      [name, { tau => terms.filtered[name][tau] }]
                  end }
            end
        end
    end
end
