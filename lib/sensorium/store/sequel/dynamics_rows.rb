# frozen_string_literal: true

module Sensorium
    module Store
        class Sequel
            # The Dynamics::Models of Store::Sequel, b kept as JSON.
            module DynamicsRows
                def dynamics(quantity)
                    rows(:dynamics, quantity, %i[location regime]).map do |row|
                        Sensorium::Dynamics::Model.new(
                            **row.slice(*Sensorium::Dynamics::Model.members),
                            b: JSON.parse(row[:b])
                        )
                    end
                end

                # Replaces the models of the same location and regime.
                def keep_dynamics(quantity, models)
                    @db.transaction do
                        models.each { drop_dynamics(quantity, it) }
                        put(:dynamics, models.map do |model|
                            model.to_h.merge(b: JSON.generate(model.b))
                        end)
                    end
                end

                private

                def drop_dynamics(quantity, model)
                    scope(:dynamics, { quantity:, location: model.location,
                                       regime: model.regime }).delete
                end
            end
        end
    end
end
