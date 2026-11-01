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

            # history: the span's Sensorium::History; priors: { location
            # => Prior }, or anything answering call(location, regime)
            # with one (nil: none).
            def initialize(history, priors: {})
                @history  = history
                @setup    = history.setup
                @priors   = priors || {}
                @series   = @setup.series
                @outside  = history.outside
                @timeline = history.timeline
            end

            def models
                @history.references.keys.flat_map { fitted(it) }
            end

            private

            def quantity = @setup.quantity.name

            def fitted(location)
                key = { location:, quantity: }
                on = @timeline.switched(location)
                reference = @history.carried(location)
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

            def regime_of(bin) = @history.regime_of(bin)

            def prior(location, regime)
                return @priors.call(location, regime) if
                    @priors.respond_to?(:call)
                @priors[location]
            end
        end
    end
end
