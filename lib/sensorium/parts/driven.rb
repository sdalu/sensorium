# frozen_string_literal: true

module Sensorium
    class Parts
        # What a location's Dynamics::Model predicts at a snapshot's
        # moment, from the inputs then: the outside's latest value among
        # the snapshot's externals, if no older than the location's
        # max_age, and the Switches on. Nothing without a model, without
        # the outside its model needs, or while a Mode holds at the
        # location (the model was fitted without those bins). Parts::Aging
        # takes it.
        class Driven
            # location: a resolved Location; model: a Dynamics::Model or
            # nil.
            def initialize(location, model, snapshot, setup)
                @location = location
                @model    = model
                @snapshot = snapshot
                @setup    = setup
            end

            # [change, variance] of a value over `hours`, in the
            # transform's space; nil as said above.
            def of(value, hours)
                return unless @model
                return unless @snapshot.holding(@location.name).empty?
                on = @snapshot.on(@location.name)
                change = @model.change(value, outside, on, hours) or return
                [change, @model.variance(hours)]
            end

            private

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
