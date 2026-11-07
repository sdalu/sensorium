# frozen_string_literal: true

module Sensorium
    class Fit
        # What a model leaves on bins it was not fitted on: each bin's
        # diff less the model's terms there, its regressors read from
        # the same Terms; a bin some regressor lacks is left out.
        class HeldOut
            # How much wider than kept tried may leave them when they
            # cannot try it (tries?): absence of evidence does not undo
            # what the rest of the season showed.
            TOLERANCE = 1.05

            # The range below which what a term adds is a constant, its
            # variation that of the rounding.
            ROUNDING = 1e-9

            # diffs: { bin => sensor - reference } of the bins held out;
            # least: the bins a term must act on there for them to judge
            # it (Balanced).
            def initialize(diffs, levels, terms, least = 1)
                @diffs  = diffs
                @levels = levels
                @terms  = terms
                @least  = least
            end

            # Whether tried leaves the bins held out no wider than kept,
            # each as the correction's (over its model's scale, as
            # Fit#ratio), over the bins both cover, those the term acts
            # on weighing as much as the others (Balanced): no wider at
            # all when they try the term (tries?) on `least` bins; within
            # TOLERANCE, all bins alike, when they cannot.
            def keeps?(kept, tried)
                found = balanced(kept, tried) if tries?(kept, tried)
                bound = found ? 1.0 : TOLERANCE
                (found || narrowing(kept, tried)) * kept.scale /
                    tried.scale <= bound
            end

            # The balanced narrowing over the bins both cover; nil when
            # the term acts on fewer than least of them.
            def balanced(kept, tried)
                before, after = [kept, tried].map { residuals(it) }
                common = after.slice(*before.keys)
                Balanced.ratio(before, common, @least,
                               Balanced.regressor(kept, tried, @terms))
            end

            # Whether the bins held out try the term: what it adds to
            # kept varies over them, by more than the rounding (its
            # range, not its p10..p90: a Switch on in a few of them
            # switches there, and they try it on those few). A Switch
            # never on there, or on throughout, adds a constant: no
            # evidence either way.
            def tries?(kept, tried)
                before, after = [kept, tried].map { residuals(it) }
                bins = before.keys & after.keys
                return false if bins.empty?
                added = bins.map { before[it] - after[it] }
                added.max - added.min > ROUNDING
            end

            # The spread tried leaves on the bins held out over the one
            # kept leaves, over the bins both cover: 1 without any.
            def narrowing(kept, tried)
                before, after = [kept, tried].map { residuals(it) }
                bins = before.keys & after.keys
                return 1.0 if bins.empty?
                wide = Stats.spread(before.values_at(*bins))
                narrow = Stats.spread(after.values_at(*bins))
                return narrow / wide if wide.positive?
                narrow.zero? ? 1.0 : Float::INFINITY
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
