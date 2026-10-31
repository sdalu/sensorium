# frozen_string_literal: true

module Sensorium
    class Parts
        # How much a reading's estimate of the reference has aged, in
        # the transform's space. With the location's Dynamics::Model
        # for the moment's regime, it is moved by the change the model
        # predicts over its age, from the inputs at the moment (the
        # outside among the snapshot's externals, if no older than
        # max_age, the Switches on), and
        # its σ² grows by q × age (hours); without one, or without the
        # outside its model needs, it stays and its σ grows by drift ×
        # age. For a device with a delta (send-on-delta), what the age
        # adds to σ² is at most delta² / 3, the delta taken into the
        # transform's space at the reading. σ is never below the
        # quantity's floor.
        class Aging
            # location: a resolved Location; model: a Dynamics::Model or
            # nil.
            def initialize(location, model, snapshot, setup)
                @location = location
                @model    = model
                @snapshot = snapshot
                @setup    = setup
            end

            # The Estimate a reading gave, aged; one with σ nil (not
            # corrected) as it is.
            def of(device, reading, estimate)
                return estimate unless estimate.sigma
                hours = @snapshot.age(reading) / 3600.0
                change, spread = modelled(estimate.value, hours) ||
                                 [0.0, (@location.drift * hours)**2]
                spread = capped(spread, device, reading)
                Estimate.new(value: estimate.value + change,
                             sigma: Math.sqrt((floored(estimate)**2) +
                                              spread))
            end

            private

            # The age's variance, at most delta² / 3 for a device with a
            # delta.
            def capped(spread, device, reading)
                delta = @location.deltas[device] or return spread
                inside = inside(reading, delta) or return spread
                [spread, (inside**2) / 3].min
            end

            # The delta as the transform takes it at the reading.
            def inside(reading, delta)
                ends = [reading.value, reading.value + delta].map do |value|
                    quantity.transform.forward(value, reading.context)
                end
                (ends.last - ends.first).abs unless ends.include?(nil)
            end

            def floored(estimate) = [estimate.sigma, quantity.floor].max

            # [change, variance] by the model; nil without one, without
            # what it needs, or while a Mode holds (the model was fitted
            # without those bins).
            def modelled(value, hours)
                return unless @model
                return unless @snapshot.holding(@location.name).empty?
                on = @snapshot.on(@location.name)
                change = @model.change(value, outside, on, hours) or return
                [change, @model.variance(hours)]
            end

            # The outside's latest value, in the transform's space; nil
            # when older than the location's max_age.
            def outside
                name = @setup.outside or return
                reading = @snapshot.latest[[nil, name]] or return
                return if @snapshot.age(reading) > @location.max_age * 60
                quantity.transform.forward(reading.value, reading.context)
            end

            def quantity = @setup.quantity
        end
    end
end
