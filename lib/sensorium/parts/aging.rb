# frozen_string_literal: true

module Sensorium
    class Parts
        # How much a reading's estimate of the reference has aged, in
        # the transform's space. With the location's Dynamics::Model
        # for the moment's regime, it is moved by the change the model
        # predicts over its age, from the inputs at the moment (the
        # outside among the snapshot's externals, the Switches on), and
        # its σ² grows by q × age (hours); without one, or without the
        # outside its model needs, it stays and its σ grows by drift ×
        # age. σ is never below the quantity's floor.
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
            def of(_device, reading, estimate)
                return estimate unless estimate.sigma
                hours = @snapshot.age(reading) / 3600.0
                change, spread = modelled(estimate.value, hours) ||
                                 [0.0, (@location.drift * hours)**2]
                Estimate.new(value: estimate.value + change,
                             sigma: Math.sqrt((floored(estimate)**2) +
                                              spread))
            end

            private

            def floored(estimate) = [estimate.sigma, quantity.floor].max

            # [change, variance] by the model; nil without one, or
            # without what it needs.
            def modelled(value, hours)
                return unless @model
                on = @snapshot.on(@location.name)
                change = @model.change(value, outside, on, hours) or return
                [change, @model.variance(hours)]
            end

            # The outside's latest value, in the transform's space.
            def outside
                name = @setup.outside or return
                reading = @snapshot.latest[[nil, name]] or return
                quantity.transform.forward(reading.value, reading.context)
            end

            def quantity = @setup.quantity
        end
    end
end
