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

                # Replaces those of the same location.
                def keep_filters(quantity, states)
                    @db.transaction do
                        states.each do |state|
                            table(:filters).where(
                                quantity:, location: state.location
                            ).delete
                        end
                        table(:filters).multi_insert(
                            states.map { filter_row(it) }
                        )
                    end
                end

                private

                def filter(row)
                    Filter::State.new(**row.slice(*Filter::State.members),
                                      at: wall_utc(row[:filtered_at]))
                end

                # The time as UTC, as the tracks' (Tracks).
                def filter_row(state)
                    state.to_h.except(:at).merge(filtered_at: state.at.utc)
                end
            end
        end
    end
end
