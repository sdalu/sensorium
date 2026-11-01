# frozen_string_literal: true

module Sensorium
    class Fit
        # What a model leaves on bins it was not fitted on: each bin's
        # diff less the model's terms there, its regressors read from
        # the same Terms; a bin some regressor lacks is left out.
        class HeldOut
            # diffs: { bin => sensor - reference } of the bins held out.
            def initialize(diffs, levels, terms)
                @diffs  = diffs
                @levels = levels
                @terms  = terms
            end

            # Whether tried leaves the bins held out no wider than kept,
            # over the bins both cover.
            def keeps?(kept, tried)
                before, after = [kept, tried].map { residuals(it) }
                bins = before.keys & after.keys
                return true if bins.empty?
                Stats.spread(after.values_at(*bins)) <=
                    Stats.spread(before.values_at(*bins))
            end

            # { bin => what the model leaves }, once per model.
            def residuals(model)
                (@residuals ||= {}.compare_by_identity)[model] ||= begin
                    terms = terms_of(model)
                    @diffs.filter_map do |bin, diff|
                        made = predicted(model, terms, bin)
                        [bin, diff - made] if made
                    end.to_h
                end
            end

            private

            # The model's offset at the bin, nil when a regressor lacks it.
            def predicted(model, terms, bin)
                pairs = terms.map { |slope, xs| [slope, xs[bin]] }
                return if pairs.any? { it.last.nil? }
                model.constant + pairs.sum { |slope, x| slope * x }
            end

            # [[slope, { bin => x }]] of the model's terms.
            def terms_of(model)
                switched(model) + model.series.map do |name, slope|
                    [slope, @terms.series[name]]
                end + linear(model)
            end

            def switched(model)
                model.switches.map do |name, term|
                    tau = model.taus[name]
                    [term, tau ? @terms.filtered[name][tau] : on(name)]
                end
            end

            # { bin => 1.0 } while the Switch was on, 0.0 otherwise.
            def on(name)
                held = @terms.switches[name]
                Hash.new { |_, bin| held.include?(bin) ? 1.0 : 0.0 }
            end

            def linear(model)
                [[model.gain, @levels],
                 [model.coefficient, @terms.candidates[model.neighbour]],
                 [model.rate, @terms.rates]].select(&:first)
            end
        end
    end
end
