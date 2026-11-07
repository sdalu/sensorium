# frozen_string_literal: true

module Sensorium
    class Regression
        # What Regression.learn takes, read from a source as the Learner
        # reads one: { y:, regressors: } over from..to. y: the readings
        # of the Setup's quantity (devices: their names, nil for all),
        # in its transform's space, binned, each bin their sum (total:
        # true, a quantity that adds up, energy) or their mean, the
        # devices added bin by bin. regressors: from the source's events
        # (Timeline), each Influence::Series' level and each
        # Influence::Switch's state (1.0 while on, else 0.0, over y's
        # bins), named by the influence for a site-wide one, NAME/
        # LOCATION per location ("heating/green-room"); pooled: true, a
        # location's influence also summed over its locations, named by
        # the influence ("heating"), over the bins every location has: a
        # term shared by the rooms, each room's share then the term ×
        # its own value.
        def self.load(source, setup, from:, to:, **options)
            pooled = options.delete(:pooled)
            y = Inputs.y(source, setup, [from, to], **options)
            timeline = Timeline.new(setup, source, from, to)
            regressors = Inputs.regressors(timeline, setup, y.keys)
            regressors = Inputs.pooled(regressors, setup) if pooled
            { y:, regressors: }
        end

        # The arithmetic of Regression.load.
        module Inputs
            module_function

            def y(source, setup, span, devices: nil, total: true)
                quantity = setup.quantity
                readings = quantity.inward(source.readings(quantity.name,
                                                           *span, devices))
                series = setup.series
                series.added(series.of(readings, total:).values)
            end

            def regressors(timeline, setup, bins)
                levels = setup.levels.flat_map do |level|
                    named(level.name, timeline.levels_of(level.name))
                end
                switches = setup.switches.flat_map do |switch|
                    named(switch.name, states(timeline.on_of(switch.name),
                                              bins))
                end
                (levels + switches).to_h
            end

            # The regressors with each location's influence summed over
            # its locations, under the influence's name.
            def pooled(regressors, setup)
                sums = (setup.levels + setup.switches).filter_map do |one|
                    parts = regressors.select do |name, _|
                        name.start_with?("#{one.name}/")
                    end
                    [one.name, summed(parts.values)] if parts.any?
                end
                regressors.merge(sums.to_h)
            end

            # { bin => sum } over the bins every series has.
            def summed(all)
                all.first.keys.filter_map do |bin|
                    values = all.map { it[bin] }
                    [bin, values.sum] unless values.include?(nil)
                end.to_h
            end

            # { where => on } as { where => { bin => 1.0 or 0.0 } }.
            def states(by_where, bins)
                by_where.transform_values do |on|
                    bins.to_h { [it, on.include?(it) ? 1.0 : 0.0] }
                end
            end

            # [[name, values]], the location's appended to name when
            # there is one.
            def named(name, by_where)
                by_where.map do |where, values|
                    [where ? "#{name}/#{where}" : name, values]
                end
            end
        end
    end
end
