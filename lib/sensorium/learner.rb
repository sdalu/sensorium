# frozen_string_literal: true

module Sensorium
    # Learns every sensor's Offset from its location's reference over a
    # span of history, for the Setup's quantity, from a source answering
    #   sensors(quantity)                     [Sensor]
    #   readings(quantity, from, to, devices) [Reading]
    #   externals(quantity, from, to)         [Reading] (optional)
    #   events(influence, from, to)           [[time, location, value]]
    #                                         (optional)
    # A location's reference is the references its Location sets, their
    # mean when several (each then learned against it too), else its
    # first sensor tagged with one of the Setup's places, in their order;
    # a location with none is left out. Bins where a Mode held, and its
    # hold after, are left out of the offsets; the values it held are
    # learned apart, as Shifts. Bins where an Influence::Transient is on
    # for a sensor are left out of its offset and Shifts alike. Each
    # regime the span covers is learned
    # apart, over its own bins.
    class Learner
        # locations: { name => Location }, those set.
        def initialize(source, setup, from:, to:, locations: {})
            @source    = source
            @setup     = setup
            @from      = from
            @to        = to
            @locations = locations
            @series    = setup.series
        end

        def learn
            sensors = @source.sensors(quantity)
            load(sensors)
            regimes = @setup.regime.covered(@from, @to)
            found = regimes.product(@references.keys)
                           .flat_map { location_offsets(*it) }
            Learned.new(quantity:, regimes:, offsets: found.map(&:first),
                        shifts: found.flat_map(&:last), sensors: @listed)
        end

        private

        def quantity = @setup.quantity.name

        def load(sensors)
            readings = @source.readings(quantity, @from, @to,
                                        Transient.names(sensors, @locations))
            @data = @series.of(@setup.quantity.inward(readings))
            @thresholds = Thresholds.new(@setup, readings)
            externals = Neighbours.externals(@source, @setup, @from, @to)
            @neighbours = Neighbours.new(@series, @setup.carry, sensors,
                                         @data.merge(externals))
            @timeline = Timeline.new(@setup, @source, @from, @to)
            @shifts = Shifts.new(@timeline, @setup)
            refer(sensors)
        end

        # The references, the sensors listed, and the transients learned
        # against the references.
        def refer(sensors)
            references = References.new(sensors, @locations, @setup)
            @references = references.all
            @listed = references.listed
            @transients = Transients.new(@setup, @data, @references,
                                         @timeline)
        end

        def location_offsets(regime, location)
            reference = Sensorium.reference_name(@references[location])
            devices(location).filter_map do |device|
                learn_device(Device.new(location:, device:, quantity:,
                                        regime:, reference:))
            end
        end

        # A sole reference is the reference; several are each learned
        # against their mean.
        def devices(location)
            refs = @references[location]
            sole = refs.one? && refs.first
            @data.keys.filter_map do |where, device|
                device if where == location && device != sole
            end
        end

        # [Offset, [Shift]] of one sensor in one regime, or nil when too
        # little was seen.
        def learn_device(one)
            all = diffs(one)
            calm = all.reject { |bin, _| @timeline.near?(one.location, bin) }
            return if calm.size < @setup.min_samples
            offset = fit(one, calm)
            [offset, @shifts.of(one, all, offset.plain)]
        end

        def fit(one, calm)
            fit = Fit.new(calm, @setup, levels: carried(one.location),
                                        **terms(one.location))
            model = fit.model
            Offset.new(**one.to_h, **Learned.values(model, fit.plain),
                       **fit.states(model))
        end

        # What a location's sensors may be fitted with (Fit::Terms).
        def terms(location)
            { switches: @timeline.switches(location)
                                 .merge(@thresholds.of(location,
                                                       @references[location])),
              filtered: @timeline.exposures(location),
              series: @timeline.series(location),
              candidates: @neighbours.gaps(location, carried(location)),
              rates: rates(location),
              held: @timeline.switched(location) }
        end

        # { bin => sensor - reference } of the regime's bins, its
        # transients' left out.
        def diffs(one)
            carried = carried(one.location)
            out = @transients.of(one.location, one.device)
            @data[[one.location, one.device]].filter_map do |bin, value|
                ref = carried[bin]
                next unless ref && regime_of(bin) == one.regime
                [bin, value - ref] unless out.include?(bin)
            end.to_h
        end

        # The reference's series, carried, once per location: the mean
        # of the references where they all have a value.
        def carried(location)
            (@carried ||= {})[location] ||= @series.mean(
                @references[location].map do |device|
                    @series.carried(@data.fetch([location, device], {}),
                                    @setup.carry)
                end
            )
        end

        # The reference's rate, per hour, once per location.
        def rates(location)
            (@rates ||= {})[location] ||= @series.rates(carried(location))
        end

        def regime_of(bin)
            (@regimes ||= {})[bin] ||= @setup.regime.of(Time.at(bin))
        end
    end
end

require_relative "learner/references"
require_relative "learner/neighbours"
require_relative "learner/thresholds"
require_relative "learner/transients"
