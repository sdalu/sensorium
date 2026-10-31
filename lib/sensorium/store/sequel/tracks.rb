# frozen_string_literal: true

module Sensorium
    module Store
        class Sequel
            # The Tracker's tracks, a row per [location, device, quantity];
            # at is kept as tracked_at, the state as a String.
            module Tracks
                def tracks(quantity)
                    rows(:tracks, quantity, %i[location device])
                        .to_h { [[it[:location], it[:device]], track(it)] }
                end

                def keep_tracks(quantity, tracks)
                    @db.transaction do
                        table(:tracks).where(quantity:).delete
                        table(:tracks).multi_insert(
                            tracks.values.map { track_row(it) }
                        )
                    end
                end

                private

                def track(row)
                    Track.new(**row.slice(*Track.members),
                              at: row[:tracked_at], state: row[:state].to_sym)
                end

                # The time in local time: without a database_timezone, Sequel
                # writes a Time's wall clock and reads it back as local.
                def track_row(track)
                    track.to_h.except(:at).merge(tracked_at: track.at.getlocal,
                                                 state: track.state.to_s)
                end
            end
        end
    end
end
