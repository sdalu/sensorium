# frozen_string_literal: true

module Sensorium
    class Tracker
        # A third for a part left with a single other: the previous
        # Fused (made with the tracks, so its jumped parts were already
        # out) moved by the location's Dynamics::Model over the time
        # since, with the inputs at the moment (Parts::Driven), in the
        # transform's space. Its σ² is the previous one's plus what the
        # model's noise adds over that time. None without a model for
        # the location and the moment's regime, without the outside it
        # needs, while a Mode holds, or when the previous Fused has no
        # value or σ, is of another location, or is older than the
        # location's max_age.
        class Witness
            # dynamics: [Dynamics::Model]; locations: { name => Location
            # }, those set; both of the setup's quantity.
            def initialize(setup, dynamics, locations)
                @setup     = setup
                @dynamics  = dynamics.to_h { [[it.location, it.regime], it] }
                @locations = locations
            end

            # The Estimate witnessing the Fused at its moment; nil as
            # said above. snapshot: the one the Fused was made from.
            def of(fused, previous, snapshot)
                before = usable(fused, previous, snapshot) or return
                hours = (fused.at - previous.at) / 3600.0
                found = driven(fused, snapshot).of(before.value, hours) or
                    return
                change, variance = found
                Estimate.new(value: before.value + change,
                             sigma: Math.sqrt((before.sigma**2) + variance))
            end

            private

            # The previous Fused's value in the transform's space, when
            # it can witness.
            def usable(fused, previous, snapshot)
                return unless snapshot && recent?(fused, previous)
                before = previous.inside
                before if before&.value && before.sigma
            end

            # Whether previous is of the location, and no older than its
            # max_age.
            def recent?(fused, previous)
                return false unless previous&.location == fused.location
                (fused.at - previous.at).between?(0,
                                                  location(fused).max_age * 60)
            end

            def driven(fused, snapshot)
                model = @dynamics[[fused.location,
                                   @setup.regime.of(fused.at)]]
                Parts::Driven.new(location(fused), model, snapshot, @setup)
            end

            def location(fused)
                @locations.fetch(fused.location) do
                    Location.default(fused.location)
                end.resolve(@setup.quantity)
            end
        end
    end
end
