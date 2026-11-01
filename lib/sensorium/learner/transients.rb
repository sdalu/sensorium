# frozen_string_literal: true

module Sensorium
    class Learner
        # The bins each sensor's Influence::Transient is on: where its
        # change against its reference goes beyond its relative
        # Threshold, the Profiles given or else learned from the same
        # History, and each influence's hold after. None when the Setup
        # names no Influence::Transient.
        class Transients
            # profiles: [Transient::Profile]; nil, learned from history.
            def initialize(history, profiles = nil)
                @setup   = history.setup
                @changes = Transient::Changes.new(history)
                @given   = profiles && Transients.indexed(profiles)
            end

            # { [location, device] => { regime => Profile } }.
            def self.indexed(profiles)
                profiles.group_by { [it.location, it.device] }
                        .transform_values do |list|
                            list.to_h { |profile| [profile.regime, profile] }
                        end
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
                return @given.fetch([location, device], {}) if @given
                @changes.of(location, device).to_h { [it.regime, it] }
            end
        end
    end
end
