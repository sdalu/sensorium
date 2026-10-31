# frozen_string_literal: true

module Sensorium
    # What the Tracker knows of one sensor's offset between two
    # learnings, for one quantity: delta, the sensor's corrected value
    # minus the truth, estimated, and its variance; the two sides of the
    # CUSUM on its innovations; at, the time of its last update; state,
    # :ok, :drifting or :jumped. regime, reference, constant and plain
    # are the fingerprint of the Offset it tracks: once the location's
    # Offset for the device has another (a relearn), the track starts
    # afresh.
    Track = Data.define(:location, :device, :quantity, :regime, :reference,
                        :constant, :plain, :delta, :variance, :cusum_up,
                        :cusum_down, :at, :state) do
        def fingerprint = [regime, reference, constant, plain]

        # Whether it tracks that Offset (nil: none).
        def tracks?(offset)
            !offset.nil? && fingerprint == Track.fingerprint(offset)
        end
    end

    class Track
        STATES = %i[ok drifting jumped].freeze

        def self.fingerprint(offset)
            [offset.regime, offset.reference, offset.constant, offset.plain]
        end

        # A track of the offset as it starts: delta 0, with that variance.
        def self.fresh(offset, variance)
            new(location: offset.location, device: offset.device,
                quantity: offset.quantity, regime: offset.regime,
                reference: offset.reference, constant: offset.constant,
                plain: offset.plain, delta: 0.0, variance:, cusum_up: 0.0,
                cusum_down: 0.0, at: nil, state: :ok)
        end
    end
end
