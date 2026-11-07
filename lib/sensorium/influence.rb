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
        # under `hold` old; a text is read as its number, "off" and
        # "false" (any case, trimmed) as false, any other as itself.
        # Learned as an additive term of the offset, kept only when it
        # narrows the spread (the radiators' water hot). tau: nil, the
        # term holds while the Switch is on; a time constant in seconds,
        # or several (TAUS), the term is term × exposure, a first-order
        # filter of the on-state, with the time constant that narrows
        # most.
        Switch = Data.define(:name, :scope, :hold, :tau) do
            def initialize(name:, scope: :site, hold: 3600, tau: nil)
                super(name: name.to_s, scope: scope.to_sym, hold:, tau:)
            end

            def on?(value)
                value = word(value) if value.is_a?(String)
                value.is_a?(Numeric) ? value.positive? : !!value
            end

            # The time constants tried, none for a hard Switch.
            def taus = Array(tau)

            private

            def word(text)
                text = text.strip
                Float(text, exception: false) ||
                    (!Switch::OFF.include?(text.downcase) && text)
            end
        end

        class Switch
            # The texts that say off, beside a number not positive.
            OFF = %w[off false].freeze
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
        # seconds; weighted: true, each value holds until the next
        # event, `hold` seconds at most, and a bin is the time-weighted
        # mean of what held in it (Series#weighted): for a level told
        # only when it changes (a valve's opening), whose events' own
        # mean says how often it changed, not where it stood. Learned
        # as coefficient × value, kept only when it narrows the spread;
        # at fusion its latest value within `hold`, the plain offset
        # when there is none.
        Series = Data.define(:name, :scope, :hold, :weighted) do
            def initialize(name:, scope: :site, hold: 3600, weighted: false)
                super(name: name.to_s, scope: scope.to_sym, hold:, weighted:)
            end
        end

        # On while the location's own reference, as it reads (before the
        # transform), was above `above` within the past `hold` seconds
        # (a humidity sensor's creep after a shower). Learned and applied
        # as a Switch; it needs no events.
        Threshold = Data.define(:name, :above, :hold) do
            def initialize(name:, above:, hold: 3600)
                super(name: name.to_s, above:, hold:)
            end

            # The bins it is on, from the reference's { bin => value }.
            def on(reference, series)
                series.spans(reference.filter_map do |bin, value|
                    bin if value > above
                end, hold)
            end
        end

        # On, for each sensor, where its change against its location's
        # reference over a window of Setup#transient_windows went beyond
        # its learned relative thresholds, and `hold` seconds after: a
        # window opened by it, a shower, the sun. Derived by the Learner from
        # the sensors' own series and their Transient::Profiles; its
        # bins are left out like a Mode's, without a Shift of their own.
        Transient = Data.define(:name, :hold) do
            def initialize(name: "transient", hold: 1800)
                super(name: name.to_s, hold:)
            end
        end

        # The location an event counts for: nil for the whole site.
        def self.where(influence, location)
            influence.scope == :site ? nil : location
        end

        # The influences of each kind, for what holds a list of them
        # (influences): a Setup, a Timeline::Plan.
        module Kinds
            def switches   = influences.grep(Influence::Switch)
            def modes      = influences.grep(Influence::Mode)
            def levels     = influences.grep(Influence::Series)
            def thresholds = influences.grep(Influence::Threshold)
            def transients = influences.grep(Influence::Transient)
        end
    end
end
