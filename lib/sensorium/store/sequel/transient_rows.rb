# frozen_string_literal: true

module Sensorium
    module Store
        class Sequel
            # The Transient::Profiles of Store::Sequel, each map of
            # thresholds kept as JSON, { "window" => [fall, rise] }.
            module TransientRows
                SCALES = %i[own relative].freeze
                KEY    = %i[location device regime].freeze

                def transients(quantity)
                    rows(:transients, quantity, %i[location device regime])
                        .map { transient(it) }
                end

                # Replaces those of the same location, device and regime.
                def keep_transients(quantity, profiles)
                    @db.transaction do
                        profiles.each do |one|
                            scope(:transients,
                                  { quantity:, **one.to_h.slice(*KEY) })
                                .delete
                        end
                        put(:transients, profiles.map { transient_row(it) })
                    end
                end

                private

                def transient(row)
                    Transient::Profile.new(
                        **row.slice(*Transient::Profile.members),
                        **SCALES.to_h { [it, scales(row[it])] }
                    )
                end

                def scales(json)
                    JSON.parse(json).to_h do |window, (fall, rise)|
                        [Integer(window),
                         Transient::Threshold.new(fall:, rise:)]
                    end
                end

                def transient_row(profile)
                    profile.to_h.merge(SCALES.to_h do |name|
                        [name, json(profile.public_send(name))]
                    end)
                end

                def json(scales)
                    JSON.generate(scales.transform_values do |threshold|
                        [threshold.fall, threshold.rise]
                    end)
                end
            end
        end
    end
end
