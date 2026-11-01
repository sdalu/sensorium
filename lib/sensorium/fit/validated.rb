# frozen_string_literal: true

module Sensorium
    class Fit
        # A Fit whose terms are chosen without the last tenth of the bins
        # (setup.min_part of them at least), each kept only when it also
        # leaves those no wider (HeldOut); the terms kept are then fitted
        # again on all the bins. With too few bins to hold any out, the
        # constant alone.
        module Validated
            module_function

            SHARE = 0.1

            # The Fit on all the diffs, its terms those chosen.
            def fit(diffs, setup, levels:, **terms)
                sorted = diffs.sort
                held = held(sorted.size, setup)
                return plain(diffs, setup, levels, terms) unless held
                chosen = Fit.new(sorted.first(sorted.size - held).to_h,
                                 setup, levels:, **terms,
                                        held_out: sorted.last(held).to_h)
                again(diffs, setup, levels, chosen)
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

            def again(diffs, setup, levels, chosen)
                model = chosen.model
                Fit.new(diffs, setup.with(gain: setup.gain && !!model.gain),
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
