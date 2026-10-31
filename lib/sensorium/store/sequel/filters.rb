# frozen_string_literal: true

module Sensorium
    module Store
        class Sequel
            # A Filter's states, a row per [location, quantity]; at is
            # kept as filtered_at.
            module Filters
                def filters(quantity)
                    table(:filters).where(quantity:).all
                                   .to_h { [it[:location], filter(it)] }
                end

                def keep_filters(quantity, states)
                    @db.transaction do
                        table(:filters).where(quantity:).delete
                        table(:filters).multi_insert(
                            states.map { filter_row(it) }
                        )
                    end
                end

                private

                def filter(row)
                    Filter::State.new(**row.slice(*Filter::State.members),
                                      at: row[:filtered_at])
                end

                # The time in local time, as the tracks' (Tracks).
                def filter_row(state)
                    state.to_h.except(:at).merge(filtered_at: state.at.getlocal)
                end
            end
        end
    end
end
