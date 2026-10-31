# frozen_string_literal: true

module Sensorium
    # How a location's sensors are learned and fused, as set by hand, for
    # one quantity:
    #   references the devices the others are corrected to, their mean
    #              when several (default: the Setup's places)
    #   sigma, drift, max_age  the Quantity's, unless set
    #   exclude    devices left out
    Location = Data.define(:name, :references, :sigma, :drift, :max_age,
                           :exclude)

    class Location
        UNSET = { sigma: nil, drift: nil, max_age: nil }.freeze

        def self.default(name) = new(name:)

        def initialize(name:, references: [], exclude: [], **settings)
            super(name:, references: Array(references),
                  exclude: Array(exclude), **UNSET, **settings)
        end

        # The settings left unset taken from the quantity.
        def resolve(quantity)
            with(sigma: sigma || quantity.sigma,
                 drift: drift || quantity.drift,
                 max_age: max_age || quantity.max_age)
        end

        # A reading's σ grown with its age (seconds).
        def aged(sigma, age) = Math.hypot(sigma, drift * age / 3600.0)
    end
end
