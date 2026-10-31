# frozen_string_literal: true

module Sensorium
    # Each sensor of a location at a moment, corrected to the location's
    # reference: a Part with its σ, or with a note saying why it does not
    # count (excluded, stale, not learned: against these references, no
    # context: the transform lacks what it needs). A sole reference
    # counts as it reads, with the location's sigma; several are each
    # corrected to their mean. raw is the reading as it reads, value and
    # sigma are in the transform's space.
    class Parts
        # value nil, and sigma nil, when the sensor does not count; sigma
        # nil alone when the location has no reference to correct it to.
        Part = Data.define(:device, :raw, :value, :sigma, :age, :note)

        # What was learned of the location in the moment's regime:
        # offsets { device => Offset }, shifts { [device, influence,
        # mode] => Shift }.
        Learning = Data.define(:offsets, :shifts)

        # location: a resolved Location; references: [device], nil when
        # it has none.
        def initialize(location, references, learning, snapshot, quantity)
            @location = location
            @name     = references&.join("+")
            @sole     = references&.one? && references.first
            @offsets  = learning.offsets.select do |_, offset|
                offset.reference == @name
            end
            @shifts   = learning.shifts
            @snapshot = snapshot
            @quantity = quantity
        end

        def all
            @snapshot.devices(@location.name).map do |device|
                part(device, @snapshot.latest[[@location.name, device]])
            end
        end

        private

        def part(device, reading)
            age = @snapshot.age(reading)
            inside = inward(reading)
            note = why_not(device, age, inside) and
                return Part.new(device:, raw: reading.value, value: nil,
                                sigma: nil, age:, note:)
            estimate = estimate(device, inside)
            sigma = estimate.sigma && @location.aged(estimate.sigma, age)
            Part.new(device:, raw: reading.value, value: estimate.value,
                     sigma:, age:, note: nil)
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

        # What the reading says of the reference; σ nil without one.
        def estimate(device, value)
            return Estimate.new(value:, sigma: nil) unless @name
            if device == @sole
                return Estimate.new(value:,
                                    sigma: @location.sigma)
            end
            @offsets[device].correct(value, on: @snapshot.on(@location.name),
                                            neighbour: neighbour(device),
                                            shifts: shifts(device))
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
                @shifts[[device, name, mode]]
            end
        end
    end
end
