# frozen_string_literal: true

module Sensorium
    class Regression
        # [Regression] of y ({ bin => value }) on the regressors ({ name
        # => { bin => value } }), named name, one per regime of the
        # Setup's that y's bins fall in with setup.min_samples of them
        # at least, in the regime's order. The terms are chosen as an
        # Offset's Series are (Fit), with the Setup's narrows, covers,
        # min_part, joint, ridge and nonnegative, and confirmed on the
        # last bins (Fit::Validated); no gain and no rate: a Regression
        # has no reference. Values and widths are kept to four
        # significant digits.
        def self.learn(y, regressors, setup, name:)
            Learner.new(y, regressors, setup, name:).all
        end

        # Learns a Regression of each regime (Regression.learn).
        class Learner
            def initialize(y, regressors, setup, name:)
                @y          = y
                @regressors = regressors.transform_keys(&:to_s)
                @setup      = setup.with(gain: false, rate: false)
                @name       = name.to_s
            end

            def all
                by = @y.group_by { |bin, _| regime_of(bin) }
                @setup.regime.names.filter_map do |regime|
                    pairs = by[regime] or next
                    one(regime, pairs.to_h)
                end
            end

            private

            def regime_of(bin) = @setup.regime.of(Time.at(bin))

            # The regime's Regression, nil under min_samples bins.
            def one(regime, diffs)
                return if diffs.size < @setup.min_samples
                learned = Fit::Validated.learn(diffs, @setup,
                                               levels: {}, series: @regressors)
                Regression.new(name: @name, quantity: @setup.quantity.name,
                               regime:, **values(learned))
            end

            def values(learned)
                model = learned.model
                residuals = model.residuals
                terms(model).merge(
                    widths(residuals.values, learned.inflation),
                    plain(learned.fit.plain),
                    samples: residuals.size,
                    block_share: Learned.block_share(residuals, @setup)
                )
            end

            def terms(model)
                { constant: round(model.constant),
                  terms: model.series.transform_values { round(it) } }
            end

            def plain(model)
                low, high = quantiles(model.residuals.values)
                { plain: round(model.constant), plain_p10: round(low),
                  plain_p90: round(high) }
            end

            # p10 and p90 of what the model leaves, widened by factor
            # about their middle.
            def widths(values, factor)
                low, high = quantiles(values)
                middle = (low + high) / 2.0
                wide = [factor, 1.0].max
                { p10: round(middle + ((low - middle) * wide)),
                  p90: round(middle + ((high - middle) * wide)) }
            end

            def quantiles(values)
                [0.1, 0.9].map { Stats.quantile(values, it) }
            end

            def round(value) = Learned.significant(value)
        end
    end
end
