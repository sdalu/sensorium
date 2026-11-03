# frozen_string_literal: true

module Sensorium
    # What a learning found, for one quantity: the regimes it covered,
    # [Offset], [Shift]. What it replaces of what was kept (gone): the
    # offsets of the sensors it learned again, and of a location whose
    # reference it found changed; nothing of a location or a regime it
    # learned nothing in, so a span that barely touches a regime, or a
    # sensor short of samples this time, loses nothing.
    # sensors: the [location, device] the source listed (nil: not
    # said); a kept offset of a sensor no longer listed gives way too, in
    # every regime.
    Learned = Data.define(:quantity, :regimes, :offsets, :shifts,
                          :sensors) do
        def initialize(sensors: nil, **) = super

        # The keys of the kept offsets that give way to this learning,
        # and of those it brings.
        def gone(kept)
            keys = offsets.to_set { Learned.key(it) }
            given = kept.select { replaced?(it, keys) || unlisted?(it) }
            given.to_set { Learned.key(it) } | keys
        end

        def unlisted?(offset)
            sensors && !sensors.include?([offset.location, offset.device])
        end

        # Whether a kept Offset's location and regime were learned again,
        # and either it was, or against another reference.
        def replaced?(offset, keys)
            reference = references[[offset.location, offset.regime]]
            reference && (reference != offset.reference ||
                          keys.include?(Learned.key(offset)))
        end

        # { [location, regime] => reference } of what was learned.
        def references
            offsets.to_h { [[it.location, it.regime], it.reference] }
        end

        # [location, device, regime] of an Offset or a Shift.
        def self.key(row) = [row.location, row.device, row.regime]

        # An Offset's values from the Fit's models, as kept.
        def self.values(model, plain)
            { **terms(model), **widths(model.residuals.values),
                samples: model.residuals.size,
                plain: plain.constant.round(3),
                **widths(plain.residuals.values, "plain_") }
        end

        def self.terms(model)
            { constant: model.constant.round(3),
              switches: model.switches.transform_values { it.round(3) },
              taus: model.taus,
              series: model.series.transform_values { significant(it) },
              gain: model.gain&.round(4), neighbour: model.neighbour,
              coefficient: model.coefficient&.round(3),
              rate: model.rate&.round(3) }
        end

        # Offset#block_share of a model's residuals ({ bin => value }):
        # the spread of their means over blocks of the quantity's
        # cusum_block, as a share of their own spread; nil with fewer
        # than MIN_BLOCKS blocks or no spread. At most 1.
        def self.block_share(residuals, setup)
            means = block_means(residuals, setup)
            spread = Stats.spread(residuals.values)
            return if means.size < Learned::MIN_BLOCKS || !spread.positive?
            [Stats.spread(means) / spread, 1.0].min.round(3)
        end

        # The residuals' means over blocks of cusum_block, those with
        # half their bins at least.
        def self.block_means(residuals, setup)
            seconds = setup.quantity.cusum_block
            least = seconds / setup.bin / 2.0
            residuals.group_by { |bin, _| bin / seconds }
                     .each_value.filter_map do |list|
                list.sum(&:last) / list.size if list.size >= least
            end
        end

        # An Offset's values with the model's widths (p10..p90, those of
        # states, off_p10..off_p90) widened by factor about their
        # middles; the plain constant's left as they are.
        def self.widened(values, factor)
            return values if factor <= 1.0
            wide = ->(low, high) { Learned.wider(low, high, factor) }
            p10, p90 = wide.call(*values.values_at(:p10, :p90))
            off_p10, off_p90 = (wide.call(values[:off_p10], values[:off_p90]) if
                                values[:off_p10])
            states = values[:states].transform_values do |low, high, *rest|
                [*wide.call(low, high), *rest]
            end
            values.merge(p10:, p90:, off_p10:, off_p90:, states:)
        end

        # [low, high] widened by factor about their middle, rounded as an
        # Offset's.
        def self.wider(low, high, factor)
            middle = (low + high) / 2.0
            [low, high].map { (middle + ((it - middle) * factor)).round(3) }
        end

        # Four significant digits: a coefficient on watts is small.
        def self.significant(value) = Float(format("%.4g", value))

        def self.widths(values, prefix = "")
            %w[p10 p90].zip([0.1, 0.9]).to_h do |key, fraction|
                [:"#{prefix}#{key}", Stats.quantile(values, fraction).round(3)]
            end
        end
    end

    class Learned
        # The blocks Learned.block_share needs.
        MIN_BLOCKS = 10
    end

    class Learner
        # One sensor of a location, in a regime, as it is learned.
        Device = Data.define(:location, :device, :quantity, :regime,
                             :reference)

        # The Shifts of a sensor: for each value a Mode held often
        # enough, how the sensor reads against its plain offset
        # meanwhile; two Modes holding at once are a value of their own
        # (Shift.named), learned over the bins they held together, which
        # belong to neither alone: what two do together is not the sum.
        class Shifts
            def initialize(timeline, setup)
                @timeline = timeline
                @setup    = setup
            end

            # one: the Device; diffs: { bin => sensor - reference }.
            def of(one, diffs, plain)
                by_mode(one.location, diffs).filter_map do |(name, mode), list|
                    next if list.size < @setup.min_shift
                    shift(one, name, mode, list.map { it - plain })
                end
            end

            private

            # { [influence, value] => [diff] } over the bins each Mode,
            # or each combination of Modes, held.
            def by_mode(location, diffs)
                diffs.each_with_object(Hash.new { [] }) do |(bin, d), all|
                    held = @timeline.modes(location, bin)
                    all[Shift.named(held)] += [d] if held.any?
                end
            end

            def shift(one, influence, mode, values)
                shift = Stats.median(values)
                Shift.new(**one.to_h.except(:reference),
                          **Learned.widths(values.map { it - shift }),
                          influence:, mode:, shift: shift.round(3),
                          samples: values.size)
            end
        end
    end
end
