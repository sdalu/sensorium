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
        # span: from:, to: and locations: ({ name => Location }, those
        # set), the History loaded from the source when none is given;
        # history:, when given, is the span instead. transients:
        # [Transient::Profile], those an Influence::Transient leaves out
        # by; learned from the History when nil.
        def initialize(source, setup, history: nil, transients: nil, **span)
            @source  = source
            @setup   = setup
            Sensorium::History.given(history, nil, nil, span) if history
            @history = history
            @span    = span
            @given   = transients
        end

        def learn
            load
            regimes = @setup.regime.covered(@history.from, @history.to)
            found = regimes.product(@references.keys)
                           .flat_map { location_offsets(*it) }
            Learned.new(quantity:, regimes:, offsets: found.map(&:first),
                        shifts: found.flat_map(&:last),
                        sensors: @history.listed)
        end

        private

        def quantity = @setup.quantity.name

        def load
            @history ||= History.load(@source, @setup, **@span)
            @data       = @history.data
            @references = @history.references
            @timeline   = @history.timeline
            @shifts     = Shifts.new(@timeline, @setup)
            @transients = Transients.new(@history, @given)
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
            fit = Fit::Validated.fit(calm, @setup,
                                     levels: carried(one.location),
                                     **terms(one.location))
            model = fit.model
            Offset.new(**one.to_h, **Learned.values(model, fit.plain),
                       **fit.states(model))
        end

        # What a location's sensors may be fitted with (Fit::Terms).
        def terms(location)
            { switches: switches(location),
              filtered: @timeline.exposures(location),
              series: @timeline.series(location),
              candidates: @history.neighbours.gaps(location,
                                                   carried(location)),
              rates: rates(location),
              held: @timeline.switched(location) }
        end

        # { name => bins on } of the Switches, the filtered ones aside,
        # and of the Thresholds.
        def switches(location)
            @timeline.switches(location)
                     .merge(@history.thresholds.of(location,
                                                   @references[location]))
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

        def carried(location) = @history.carried(location)
        def regime_of(bin) = @history.regime_of(bin)
        def rates(location) = @history.rates(location)
    end
end

require_relative "learner/references"
require_relative "learner/neighbours"
require_relative "learner/thresholds"
require_relative "learner/transients"
