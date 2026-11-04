# frozen_string_literal: true

module Sensorium
    # What is known of one quantity, as a store keeps it: offsets
    # [Offset], shifts [Shift], locations { name => Location }, those
    # set, tracks { [location, device] => Track }, dynamics
    # [Dynamics::Model], transients [Transient::Profile] and
    # collocations [Collocation]. The Fusion, the Tracker and the
    # Transient::Detector each take the part they need of it
    # (knowledge:), as a Tick does; none takes the dynamics, kept for
    # the caller.
    Knowledge = Data.define(:offsets, :shifts, :locations, :tracks,
                            :dynamics, :transients, :collocations) do
        def initialize(offsets: [], shifts: [], locations: {}, tracks: {},
                       dynamics: [], transients: [], collocations: [])
            super
        end
    end

    class Knowledge
        # The Knowledge given, or one of the keywords given instead: those
        # required must be there, no other than required and optional
        # may. Not both.
        def self.given(knowledge, keywords, required, optional = [])
            if knowledge
                return knowledge if keywords.empty?
                raise ArgumentError, "knowledge: or keywords, not both"
            end
            check(keywords.keys, required, optional)
            new(**keywords)
        end

        def self.check(keys, required, optional)
            missing = required - keys
            raise ArgumentError, "missing: #{missing.join(", ")}" if
                missing.any?
            unknown = keys - required - optional
            raise ArgumentError, "unknown: #{unknown.join(", ")}" if
                unknown.any?
        end
        private_class_method :check

        # The Offset of a sensor in a regime (the Setup's regime.of(at));
        # nil when it was not learned there.
        def offset(location, device, regime)
            offsets.find { Learned.key(it) == [location, device, regime] }
        end

        # The Shift of a sensor in a regime for what holds (holding:
        # [[name, value]] of the Modes, as Snapshot#holding gives them,
        # named as one by Shift.named); nil when none holds or none was
        # learned for it. A Mode holding without a Shift is still
        # held: Offset#predict and #correct then take held: true.
        def shift(location, device, regime, holding)
            return if holding.empty?
            key = [location, device, regime, *Shift.named(holding)]
            shifts.find { [*Learned.key(it), it.influence, it.mode] == key }
        end

        # The Track of a sensor while it follows that Offset (its
        # fingerprint); nil without one, or after a relearn.
        def track(location, device, offset)
            found = tracks[[location, device]] or return
            found if found.fingerprint == Track.fingerprint(offset)
        end
    end
end
