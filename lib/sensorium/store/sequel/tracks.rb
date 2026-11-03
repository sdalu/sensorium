# frozen_string_literal: true

module Sensorium
    module Store
        class Sequel
            # The Tracker's tracks, a row per [location, device, quantity];
            # at is kept as tracked_at, the state as a String.
            module Tracks
                def tracks(quantity)
                    scope(:tracks, { quantity: })
                        .select_append(*texts(%i[tracked_at block_at]))
                        .order(name_of(:location), name_of(:device)).all
                        .to_h { [[it[:location], it[:device]], track(it)] }
                end

                # Replaces those of the same location and device.
                def keep_tracks(quantity, tracks)
                    @db.transaction do
                        tracks.each_key do |location, device|
                            scope(:tracks, { quantity:, location:,
                                             device: }).delete
                        end
                        put(:tracks, tracks.values.map { track_row(it) })
                    end
                end

                private

                # A row kept before the blocks (block_count NULL) starts
                # a block afresh.
                def track(row)
                    Track.new(**row.slice(*Track.members),
                              block_sum: row[:block_sum] || 0.0,
                              block_noise: row[:block_noise] || 0.0,
                              block_count: row[:block_count] || 0,
                              block_at: utc_at(row, :block_at),
                              at: utc_at(row, :tracked_at),
                              state: row[:state].to_sym)
                end

                # The time as UTC, independently of the database's own
                # timezone: Sequel's own conversion is sidestepped, so
                # the repeated autumn hour does not round-trip an hour
                # off.
                def track_row(track)
                    track.to_h.except(:at)
                         .merge(tracked_at: track.at.getutc,
                                block_at: track.block_at&.getutc,
                                state: track.state.to_s)
                end
            end
        end
    end
end
