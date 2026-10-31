# frozen_string_literal: true

module Sensorium
    # How a location's sensors are learned and fused, as set by hand, for
    # one quantity:
    #   references the devices the others are corrected to, their mean
    #              when several (default: the Setup's places)
    #   sigma, drift, max_age  the Quantity's, unless set
    #   exclude    devices left out
    #   deltas     { device => the change it reports on }, as the
    #              quantity reads (before the transform): a device that
    #              reports only when its value moved by that much
    #              (send-on-delta)
    Location = Data.define(:name, :references, :sigma, :drift, :max_age,
                           :exclude, :deltas)

    class Location
        UNSET = { sigma: nil, drift: nil, max_age: nil }.freeze

        def self.default(name) = new(name:)

        def initialize(name:, references: [], exclude: [], deltas: {},
                       **settings)
            super(name:, references: Array(references),
                  exclude: Array(exclude),
                  deltas: (deltas || {}).transform_keys(&:to_s),
                  **UNSET, **settings)
        end

        # The settings left unset taken from the quantity.
        def resolve(quantity)
            with(sigma: sigma || quantity.sigma,
                 drift: drift || quantity.drift,
                 max_age: max_age || quantity.max_age)
        end
    end
end
