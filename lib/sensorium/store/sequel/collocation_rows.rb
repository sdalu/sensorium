# frozen_string_literal: true

module Sensorium
    module Store
        class Sequel
            # The Collocations of Store::Sequel, sigmas kept as JSON.
            module CollocationRows
                def collocations(quantity)
                    rows(:collocations, quantity, %i[location regime])
                        .map do |row|
                            Sensorium::Collocation.new(
                                **row.slice(*Sensorium::Collocation.members),
                                sigmas: JSON.parse(row[:sigmas])
                            )
                        end
                end

                # Replaces those of the same location and regime.
                def keep_collocations(quantity, list)
                    @db.transaction do
                        list.each do |one|
                            table(:collocations)
                                .where(quantity:, location: one.location,
                                       regime: one.regime).delete
                        end
                        table(:collocations).multi_insert(list.map do |one|
                            one.to_h.merge(sigmas: JSON.generate(one.sigmas))
                        end)
                    end
                end
            end
        end
    end
end
