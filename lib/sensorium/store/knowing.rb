# frozen_string_literal: true

module Sensorium
    module Store
        # What both stores answer alike, from their other methods.
        module Knowing
            # The Knowledge of a quantity: all the store keeps of it.
            def knowledge(quantity)
                Sensorium::Knowledge.new(
                    offsets: offsets(quantity), shifts: shifts(quantity),
                    locations: locations(quantity), tracks: tracks(quantity),
                    dynamics: dynamics(quantity),
                    transients: transients(quantity),
                    collocations: collocations(quantity)
                )
            end
        end
    end
end
