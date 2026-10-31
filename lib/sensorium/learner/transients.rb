# frozen_string_literal: true

module Sensorium
    class Learner
        # The bins each sensor's Influence::Transient is on: where its
        # change against its reference goes beyond its relative
        # Threshold, the Profiles learned from the same span, and each
        # influence's hold after. None when the Setup names no
        # Influence::Transient.
        class Transients
            # data, references, timeline: the Learner's.
            def initialize(setup, data, references, timeline)
                @setup   = setup
                @changes = Transient::Changes.new(setup, data, references,
                                                  timeline)
            end

            # The Set of bins left out of a sensor's offset.
            def of(location, device)
                return Set.new if @setup.transients.empty?
                (@of ||= {})[[location, device]] ||= begin
                    jumps = @changes.jumps(location, device,
                                           profiles(location, device))
                    @setup.transients.map do |transient|
                        @setup.series.spans(jumps, transient.hold)
                    end.reduce(:|)
                end
            end

            private

            def profiles(location, device)
                @changes.of(location, device).to_h { [it.regime, it] }
            end
        end
    end
end
