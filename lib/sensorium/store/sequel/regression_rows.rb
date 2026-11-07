# frozen_string_literal: true

module Sensorium
    module Store
        class Sequel
            # The Regressions of Store::Sequel, their terms kept as JSON,
            # and their Tracks, a row per [name, quantity] (a
            # Regression's Track: location and reference nil, device its
            # name).
            module RegressionRows
                def regressions(quantity)
                    rows(:regressions, quantity, %i[name regime]).map do |row|
                        Regression.new(**row.slice(*Regression.members),
                                       terms: JSON.parse(row[:terms]))
                    end
                end

                # Replaces those of the same name and regime.
                def keep_regressions(quantity, list)
                    Store.same_quantity!(quantity, list)
                    @db.transaction do
                        list.each do |one|
                            scope(:regressions, { quantity:, name: one.name,
                                                  regime: one.regime }).delete
                        end
                        put(:regressions, list.map { regression_row(it) })
                    end
                end

                # { name => Track }.
                def regression_tracks(quantity)
                    scope(:regression_tracks, { quantity: })
                        .select_append(*texts(%i[tracked_at block_at]))
                        .order(name_of(:name)).all
                        .to_h { [it[:name], regression_track(it)] }
                end

                # tracks: { name => Track }; replaces those of the same
                # name.
                def keep_regression_tracks(quantity, tracks)
                    Store.same_quantity!(quantity, tracks.values)
                    @db.transaction do
                        tracks.each_key do |name|
                            scope(:regression_tracks, { quantity:, name: })
                                .delete
                        end
                        put(:regression_tracks,
                            tracks.values.map { regression_track_row(it) })
                    end
                end

                # A Regression gone for good: its rows in every regime,
                # and its track.
                def forget_regression(quantity, name)
                    @db.transaction do
                        %i[regressions regression_tracks].each do |table|
                            scope(table, { quantity:, name: }).delete
                        end
                    end
                end

                private

                def regression_row(one)
                    one.to_h.merge(terms: JSON.generate(one.terms))
                end

                def regression_track(row)
                    Track.new(**row.slice(*Track.members),
                              location: nil, device: row[:name],
                              reference: nil, at: utc_at(row, :tracked_at),
                              block_at: utc_at(row, :block_at),
                              state: row[:state].to_sym)
                end

                def regression_track_row(track)
                    track.to_h.except(:at, :location, :device, :reference)
                         .merge(name: track.device,
                                tracked_at: track.at.getutc,
                                block_at: track.block_at&.getutc,
                                state: track.state.to_s)
                end
            end
        end
    end
end
