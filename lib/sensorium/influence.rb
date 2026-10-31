# frozen_string_literal: true

module Sensorium
    # What runs near the sensors and moves them, told by the source as
    # events [[time, location, value]] (source.events(name, from, to)).
    # scope :site: an event anywhere counts everywhere (one boiler for
    # the house); :location: only where it happened. hold: seconds an
    # event still counts after it.
    module Influence
        # The time constants a filtered Switch is tried with (seconds).
        TAUS = [600, 1800, 3600, 7200].freeze

        # On or off: on while an event with a true or positive value is
        # under `hold` old. Learned as an additive term of the offset,
        # kept only when it narrows the spread (the radiators' water
        # hot). tau: nil, the term holds while the Switch is on; a time
        # constant in seconds, or several (TAUS), the term is term ×
        # exposure, a first-order filter of the on-state, with the time
        # constant that narrows most.
        Switch = Data.define(:name, :scope, :hold, :tau) do
            def initialize(name:, scope: :site, hold: 3600, tau: nil)
                super(name: name.to_s, scope: scope.to_sym, hold:, tau:)
            end

            def on?(value) = value.is_a?(Numeric) ? value.positive? : !!value

            # The time constants tried, none for a hard Switch.
            def taus = Array(tau)
        end

        # A state with values (the aircon heating or cooling): the bins
        # under it, and `hold` after, are left out of the offset; each
        # value is learned apart as a Shift over the plain offset.
        Mode = Data.define(:name, :scope, :hold) do
            def initialize(name:, scope: :location, hold: 1800)
                super(name: name.to_s, scope: scope.to_sym, hold:)
            end

            def value(raw) = raw && raw != false ? raw.to_s : nil
        end

        # A level (the PV inverter's power, W): events with numeric
        # values, binned as their mean per bin and carried `hold`
        # seconds. Learned as coefficient × value, kept only when it
        # narrows the spread; at fusion its latest value within `hold`,
        # the plain offset when there is none.
        Series = Data.define(:name, :scope, :hold) do
            def initialize(name:, scope: :site, hold: 3600)
                super(name: name.to_s, scope: scope.to_sym, hold:)
            end
        end

        # The location an event counts for: nil for the whole site.
        def self.where(influence, location)
            influence.scope == :site ? nil : location
        end
    end
end
