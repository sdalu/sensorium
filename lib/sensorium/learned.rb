# frozen_string_literal: true

module Sensorium
    # What a learning found, for one quantity: the regimes it covered,
    # [Offset], [Shift]. What it replaces of what was kept (gone): the
    # offsets of the sensors it learned again, and of a location whose
    # reference it found changed; nothing of a location or a regime it
    # learned nothing in, so a span that barely touches a regime, or a
    # sensor short of samples this time, loses nothing.
    Learned = Data.define(:quantity, :regimes, :offsets, :shifts) do
        # The keys of the kept offsets that give way to this learning,
        # and of those it brings.
        def gone(kept)
            keys = offsets.to_set { Learned.key(it) }
            given = kept.select { replaced?(it, keys) }
            given.to_set { Learned.key(it) } | keys
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
              series: model.series.transform_values { significant(it) },
              gain: model.gain&.round(4), neighbour: model.neighbour,
              coefficient: model.coefficient&.round(3),
              rate: model.rate&.round(3) }
        end

        # Four significant digits: a coefficient on watts is small.
        def self.significant(value) = Float(format("%.4g", value))

        def self.widths(values, prefix = "")
            %w[p10 p90].zip([0.1, 0.9]).to_h do |key, fraction|
                [:"#{prefix}#{key}", Stats.quantile(values, fraction).round(3)]
            end
        end
    end

    class Learner
        # One sensor of a location, in a regime, as it is learned.
        Device = Data.define(:location, :device, :quantity, :regime,
                             :reference)

        # The Shifts of a sensor: for each value a Mode held often
        # enough, how the sensor reads against its plain offset
        # meanwhile.
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

            def by_mode(location, diffs)
                diffs.each_with_object(Hash.new { [] }) do |(bin, d), all|
                    @timeline.modes(location, bin).each { all[it] += [d] }
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
