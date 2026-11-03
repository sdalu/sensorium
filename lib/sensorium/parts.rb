# frozen_string_literal: true

module Sensorium
    # Each sensor of a location at a moment, corrected to the location's
    # reference: a Part with its σ, or with a note saying why it does not
    # count (excluded, stale, not learned: against these references, no
    # context: the transform lacks what it needs, jumped: its Track
    # says so). A sole reference counts as it reads, with the location's
    # sigma; several are each corrected to their mean. A sensor with a
    # Track has its delta taken out after, and is noted drifting while
    # its Track is. raw is the reading as it reads, value and sigma are
    # in the transform's space.
    class Parts
        # value nil, and sigma nil, when the sensor does not count; sigma
        # nil alone when the location has no reference to correct it to.
        # time: the reading's, as it was told.
        Part = Data.define(:device, :raw, :value, :sigma, :age, :time,
                           :note)

        # What was learned of the location in the moment's regime:
        # offsets { device => Offset }, shifts { [device, influence,
        # mode] => Shift }, tracks { device => Track } (Tracker).
        Learning = Data.define(:offsets, :shifts, :tracks) do
            def initialize(tracks: {}, **) = super
        end

        # location: a resolved Location; references: [device], nil when
        # it has none.
        def initialize(location, references, learning, snapshot, setup)
            @location = location
            @name     = references && Sensorium.reference_name(references)
            @sole     = references&.one? && references.first
            @offsets  = learning.offsets
                                .select { |_, one| one.reference == @name }
            @learning = learning
            @snapshot = snapshot
            @quantity = setup.quantity
            @inputs   = Inputs.new(location, references, snapshot, setup)
            @aging    = Aging.new(location, snapshot, setup)
        end

        def all = pairs.map(&:first)

        # [[Part, the Part before its Track was applied]], the two the
        # same Part for a sensor without a Track.
        def pairs
            @snapshot.devices(@location.name).map do |device|
                part = part(device,
                            @snapshot.latest[[@location.name, device]])
                [tracked(part), part]
            end
        end

        private

        def part(device, reading)
            age = @snapshot.age(reading)
            inside = inward(reading)
            note = why_not(device, age, inside) and
                return Part.new(device:, raw: reading.value, value: nil,
                                sigma: nil, age:, time: reading.time, note:)
            estimate = @aging.of(device, reading, estimate(device, inside))
            Part.new(device:, raw: reading.value, value: estimate.value,
                     sigma: estimate.sigma, age:, time: reading.time,
                     note: nil)
        end

        def why_not(device, age, inside)
            if @location.exclude.include?(device) then "excluded"
            elsif age > @location.max_age * 60 then "stale"
            elsif inside.nil? then "no context"
            elsif @name && device != @sole && !@offsets[device]
                "not learned"
            end
        end

        def inward(reading)
            @quantity.transform.forward(reading.value, reading.context)
        end

        # What the reading says of the reference; without one, the
        # reading as it reads, with the location's σ.
        def estimate(device, value)
            return Estimate.new(value:, sigma: @location.sigma) unless @name
            if device == @sole
                return Estimate.new(value:,
                                    sigma: @location.sigma)
            end
            @offsets[device].correct(value, shifts: shifts(device),
                                            **moment(device))
        end

        # What holds for a sensor's model at the moment: Offset::Moment.
        def moment(device)
            { on: @inputs.on, neighbour: neighbour(device),
              **@inputs.of(@offsets[device]) }
        end

        # The neighbour's value, when it is fresh enough.
        def neighbour(device)
            name = @offsets[device].neighbour or return
            reading = @snapshot.neighbour(name) or return
            return if @snapshot.age(reading) > 2 * @location.max_age * 60
            inward(reading)
        end

        def shifts(device)
            @snapshot.holding(@location.name).filter_map do |name, mode|
                @learning.shifts[[device, name, mode]]
            end
        end

        # The part with its Track applied (Track#apply), when it counts.
        def tracked(part)
            track = @learning.tracks[part.device]
            track && part.value ? track.apply(part) : part
        end
    end
end

require_relative "parts/inputs"
require_relative "parts/aging"
