# frozen_string_literal: true

module Sensorium
    # What is measured, and the defaults a Location takes for it, in the
    # transform's units (the space it is learned and fused in):
    #   sigma     a sole reference's own error (one σ)
    #   drift     how fast the value may move, per hour: an old reading
    #             is trusted less by drift × its age
    #   max_age   minutes after which a reading is not used
    #   robust_nu the Student-t ν the Fusion reweights parts by: lower
    #             downweights a disagreeing part harder (4)
    #   outlier_factor a part's reweighted share of 1/σ² below which it
    #             is noted "outlier" (0.2)
    #   floor     the least σ a reading is given, however tight its
    #             offset was learned (a quarter of sigma unless set)
    #   transform Transform::Identity, Transform::AbsoluteHumidity…
    # and how the Tracker follows each sensor's offset:
    #   track_q   how far it may wander, a variance per hour ((sigma/2)²
    #             a day unless set)
    #   cusum_k   the slack of the CUSUM on standardised innovations (0.5)
    #   cusum_h   the CUSUM above which the track has jumped (5)
    #   drift_alarm, drift_clear  |delta| in Offset σ above which it
    #             drifts (3), below which it is back (2)
    Quantity = Data.define(:name, :unit, :sigma, :drift, :max_age,
                           :robust_nu, :outlier_factor, :floor, :transform,
                           :track_q, :cusum_k, :cusum_h, :drift_alarm,
                           :drift_clear)

    class Quantity
        DEFAULTS = { unit: nil, max_age: 60, robust_nu: 4.0,
                     outlier_factor: 0.2, floor: nil,
                     transform: Transform::Identity, track_q: nil,
                     cusum_k: 0.5, cusum_h: 5.0, drift_alarm: 3.0,
                     drift_clear: 2.0 }.freeze

        def initialize(name:, sigma:, **settings)
            given = DEFAULTS.merge(settings)
            super(**given, name: name.to_s, sigma:,
                           floor: given[:floor] || (sigma / 4.0),
                           track_q: given[:track_q] || ((sigma**2) / 96.0))
        end

        # The readings taken into the transform's space, those it cannot
        # take left out.
        def inward(readings)
            readings.filter_map do |reading|
                value = transform.forward(reading.value, reading.context)
                reading.with(value:) if value
            end
        end
    end
end
