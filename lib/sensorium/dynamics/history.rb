# frozen_string_literal: true

module Sensorium
    module Dynamics
        # Each location's steps over a span of history, by regime, and
        # the Models fitted on them.
        class History
            # One bin's step: bin; gap, outside - r (nil without an
            # outside); on, the names of the Switches on; change,
            # r(t + bin) - r(t).
            Step = Data.define(:bin, :gap, :on, :change)

            # priors: { location => Prior }, or anything answering
            # call(location, regime) with one (nil: none).
            def initialize(source, setup, span, locations: {}, priors: {})
                @source    = source
                @setup     = setup
                @span      = span
                @locations = locations
                @priors    = priors || {}
                @series    = setup.series
            end

            def models
                sensors = @source.sensors(quantity)
                references = Learner::References.new(sensors, @locations,
                                                     @setup).all
                load(references.values.flatten.uniq)
                references.flat_map { |where, devices| fitted(where, devices) }
            end

            private

            def quantity = @setup.quantity.name

            def load(devices)
                readings = @source.readings(quantity, *@span, devices)
                @data     = @series.of(@setup.quantity.inward(readings))
                @outside  = outside
                @timeline = Timeline.new(@setup, @source, *@span)
            end

            # { bin => value } of the outside, carried; nil without one.
            def outside
                name = @setup.outside or return
                return {} unless @source.respond_to?(:externals)
                readings = @source.externals(quantity, *@span)
                                  .select { it.device == name }
                @series.carried(@series.means(@setup.quantity
                                                    .inward(readings)),
                                @setup.carry)
            end

            def fitted(location, devices)
                key = { location:, quantity: }
                on = @timeline.switched(location)
                reference = reference(location, devices)
                forecast = Forecast.new(reference, @outside, on)
                steps(location, reference, on).filter_map do |regime, list|
                    Validation.model(key.merge(regime:), list, @setup,
                                     forecast, prior(location, regime))
                end
            end

            # { regime => [Step] } of a location, the bins where a Mode
            # held, or held within its hold, left out.
            def steps(location, reference, on)
                found = reference.filter_map do |bin, r|
                    next if @timeline.near?(location, bin)
                    step = step(reference, bin, r, on) or next
                    [regime_of(bin), step]
                end
                found.group_by(&:first).transform_values { it.map(&:last) }
            end

            def step(reference, bin, r, on)
                after = reference[bin + @series.width] or return
                return if @outside && !@outside[bin]
                Step.new(bin:, gap: @outside && (@outside[bin] - r),
                         change: after - r,
                         on: on.filter_map do |name, bins|
                             name if bins.include?(bin)
                         end)
            end

            # The references' mean, each carried, as the Learner's.
            def reference(location, devices)
                @series.mean(devices.map do |device|
                    @series.carried(@data.fetch([location, device], {}),
                                    @setup.carry)
                end)
            end

            def regime_of(bin)
                (@regimes ||= {})[bin] ||= @setup.regime.of(Time.at(bin))
            end

            def prior(location, regime)
                return @priors.call(location, regime) if
                    @priors.respond_to?(:call)
                @priors[location]
            end
        end
    end
end
