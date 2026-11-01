# frozen_string_literal: true

module Sensorium
    # A span of history of a Setup's quantity, read once from a source
    # (as the Learner's) and shared by the learners: Learner, Dynamics,
    # Collocation and Transient each take one as history:. It holds the
    # sensors; the references (as References finds them) and the
    # sensors listed; the binned series in the transform's space, of the
    # sensors and the references set (data) and of the externals; the
    # Thresholds, from the readings as they read; the Timeline; and,
    # once each, every location's carried reference series, its rate
    # and the Neighbours.
    class History
        attr_reader :setup, :from, :to, :locations, :sensors, :references,
                    :listed, :data, :externals, :thresholds, :timeline

        # locations: { name => Location }, those set.
        def self.load(source, setup, from:, to:, locations: {})
            sensors = source.sensors(setup.quantity.name)
            readings = source.readings(setup.quantity.name, from, to,
                                       Transient.names(sensors, locations))
            externals = Learner::Neighbours.externals(source, setup, from, to)
            timeline = Timeline.new(setup, source, from, to)
            new(setup, [from, to], sensors:, readings:, locations:, externals:,
                                   timeline:)
        end

        # readings: [Reading], as the source told them; externals:
        # { [nil, device] => { bin => value } }.
        def initialize(setup, span, sensors:, readings:, **given)
            @setup  = setup
            @series = setup.series
            @from, @to = span
            @sensors = sensors
            @data = @series.of(setup.quantity.inward(readings))
            @thresholds = Learner::Thresholds.new(setup, readings)
            @locations, @externals, @timeline =
                given.values_at(:locations, :externals, :timeline)
            refer
        end

        def quantity = @setup.quantity.name

        # A device's binned series, carried `carry`, once each.
        def carried_of(location, device)
            (@carried_of ||= {})[[location, device]] ||=
                @series.carried(@data.fetch([location, device], {}),
                                @setup.carry)
        end

        # The reference's series, carried, once per location: the mean
        # of the references where they all have a value.
        def carried(location)
            (@carried ||= {})[location] ||= @series.mean(
                @references.fetch(location).map { carried_of(location, it) }
            )
        end

        # The reference's rate, per hour, once per location.
        def rates(location)
            (@rates ||= {})[location] ||= @series.rates(carried(location))
        end

        # { bin => value } of the external Setup#outside names, carried;
        # nil without one.
        def outside
            name = @setup.outside or return
            @outside ||= @series.carried(@externals.fetch([nil, name], {}),
                                         @setup.carry)
        end

        # What a location's sensors may be learned against beside their
        # reference.
        def neighbours
            @neighbours ||= Learner::Neighbours.new(
                @series, @setup.carry, @sensors, @data.merge(@externals)
            )
        end

        def regime_of(bin)
            (@regimes ||= {})[bin] ||= @setup.regime.of(Time.at(bin))
        end

        private

        def refer
            found = Learner::References.new(@sensors, @locations, @setup)
            @references = found.all
            @listed = found.listed
        end
    end
end
