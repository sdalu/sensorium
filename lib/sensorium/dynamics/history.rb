# frozen_string_literal: true

module Sensorium
    module Dynamics
        # Each location's steps over a span of history, by regime, and
        # the Models fitted on them.
        class History
            # One bin's step: gap, outside - r (nil without an outside);
            # on, the names of the Switches on; change, r(t + bin) - r(t).
            Step = Data.define(:gap, :on, :change)

            def initialize(source, setup, from, to, locations)
                @source    = source
                @setup     = setup
                @span      = [from, to]
                @locations = locations
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
                steps(location, devices).filter_map do |regime, list|
                    Regression.model(key.merge(regime:), list, @setup)
                end
            end

            # { regime => [Step] } of a location.
            def steps(location, devices)
                on = @timeline.switched(location)
                reference = reference(location, devices)
                found = reference.filter_map do |bin, r|
                    step = step(reference, bin, r, on) or next
                    [regime_of(bin), step]
                end
                found.group_by(&:first).transform_values { it.map(&:last) }
            end

            def step(reference, bin, r, on)
                after = reference[bin + @series.width] or return
                return if @outside && !@outside[bin]
                Step.new(gap: @outside && (@outside[bin] - r),
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
        end
    end
end
