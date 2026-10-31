# frozen_string_literal: true

module Sensorium
    module Transient
        # The transients of a Snapshot: for each sensor with a Profile in
        # the moment's regime, its latest reading less the one at or
        # before the latest's time less each window (no older than the
        # carry before it, as the learned series were carried), in the
        # transform's space, standardised by the sensor's own Scale; an
        # Event where |z| is at least transient_z.
        class Detector
            # profiles: [Profile] of the setup's quantity.
            def initialize(setup, profiles:)
                @setup    = setup
                @profiles = profiles.to_h do |profile|
                    [[profile.location, profile.device, profile.regime],
                     profile]
                end
            end

            # [Event] of the snapshot.
            def events(snapshot)
                regime = @setup.regime.of(snapshot.at)
                snapshot.latest.flat_map do |key, latest|
                    profile = @profiles[[*key, regime]] or next []
                    of(profile, latest, snapshot.history.fetch(key, []))
                end
            end

            private

            def of(profile, latest, history)
                profile.own.filter_map do |window, scale|
                    change = change(latest, history, window) or next
                    z = scale.z(change)
                    event(profile, z, window, latest) if
                        z.abs >= @setup.transient_z
                end
            end

            def event(profile, z, window, latest)
                Event.new(location: profile.location, device: profile.device,
                          direction: z.negative? ? :fall : :rise, z:,
                          window:, at: latest.time)
            end

            # The change over the window, nil without a reading to start
            # from.
            def change(latest, history, window)
                before = start(history, latest.time - window) or return
                values = @setup.quantity.inward([before, latest])
                values.last.value - values.first.value if values.size == 2
            end

            # The reading at or before the time, no older than the carry
            # before it.
            def start(history, time)
                before = history.reverse_each.find { it.time <= time }
                before if before && time - before.time <= @setup.carry
            end
        end
    end
end
