# frozen_string_literal: true

module Sensorium
    class Fit
        # The narrowing a term brings, judged with the bins it acts on
        # weighted as much as the others: a term acting on a few bins
        # (an aircon zone calling one hour in a hundred, a Switch
        # seldom on) moves p10..p90 of all the bins not at all, whatever
        # it explains there, and a plain spread would never keep it. The
        # bins a term acts on are those where its regressor departs from
        # the regressor's median, beyond the rounding (a Switch: where
        # it is in its rarer state); a term with no regressor of its own
        # (a gain, a neighbour, a rate), or whose regressor departs on
        # most bins, is judged on every bin alike, by the plain spread.
        # The regressor, not what the term adds: fitted together, the
        # terms chosen before move a little with each one tried, and
        # would count every bin they act on. Those acting weigh half,
        # the rest half.
        module Balanced
            module_function

            # after's spread over before's, both { bin => residual } over
            # after's bins, before covering them; regressor: { bin =>
            # value } of the term's own (absent: 0), nil for none. 1
            # when neither spreads, infinite when only after does; nil
            # when the term acts on fewer than least bins.
            def ratio(before, after, least, regressor = nil)
                bins = after.keys
                weights = weights(bins, regressor, least)
                return if weights == false
                wide, narrow = [before, after].map do |residuals|
                    spread(residuals.values_at(*bins), weights)
                end
                return narrow / wide if wide.positive?
                narrow.zero? ? 1.0 : Float::INFINITY
            end

            # The weights of the bins, those acting half, the others
            # half; nil (each alike) without a regressor, or one acting
            # on most bins; false when it acts on fewer than least.
            def weights(bins, regressor, least)
                return unless regressor
                acting = acting(bins.map { regressor[it] || 0.0 })
                count = acting.count(true)
                rest = acting.size - count
                return if count >= rest
                return false if count < least
                acting.map { it ? 0.5 / count : 0.5 / rest }
            end

            # Whether each value departs from the median of them all.
            def acting(values)
                mid = Stats.median(values)
                low, high = values.minmax
                least = Fit::HeldOut::ROUNDING * [high - low, 1.0].max
                values.map { (it - mid).abs > least }
            end

            # { bin => value } of the regressor tried brings over kept: a
            # Series' values, a filtered Switch's exposures at its tau,
            # a hard Switch's state (1.0 on, else 0.0); nil for a linear
            # term.
            def regressor(kept, tried, terms)
                name = new_key(kept.series, tried.series) and
                    return terms.series[name]
                name = new_key(kept.switches, tried.switches) or return
                tau = tried.taus[name]
                tau ? terms.filtered[name][tau] : state(terms, name)
            end

            # { bin => 1.0 while the Switch was on, else 0.0 }.
            def state(terms, name)
                on = terms.switches.fetch(name) do
                    terms.held.fetch(name, Set.new)
                end
                Hash.new { |_, bin| on.include?(bin) ? 1.0 : 0.0 }
            end

            def new_key(before, after) = (after.keys - before.keys).first

            def spread(values, weights)
                return Stats.spread(values) unless weights
                Stats.weighted_quantile(values, weights, 0.9) -
                    Stats.weighted_quantile(values, weights, 0.1)
            end
        end
    end
end
