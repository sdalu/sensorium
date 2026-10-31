# frozen_string_literal: true

module Sensorium
    # What runs near the sensors and moves them, told by the source as
    # events [[time, location, value]] (source.events(name, from, to)).
    # scope :site: an event anywhere counts everywhere (one boiler for
    # the house); :location: only where it happened. hold: seconds an
    # event still counts after it.
    module Influence
        # On or off: on while an event with a true or positive value is
        # under `hold` old. Learned as an additive term of the offset,
        # kept only when it narrows the spread (the radiators' water
        # hot).
        Switch = Data.define(:name, :scope, :hold) do
            def initialize(name:, scope: :site, hold: 3600)
                super(name: name.to_s, scope: scope.to_sym, hold:)
            end

            def on?(value) = value.is_a?(Numeric) ? value.positive? : !!value
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

        # The location an event counts for: nil for the whole site.
        def self.where(influence, location)
            influence.scope == :site ? nil : location
        end
    end
end
