# frozen_string_literal: true

module Sensorium
    module Transient
        # The changes of a span's sensors over each of the Setup's
        # transient windows, from their binned series (in the
        # transform's space) carried `carry`, the bins under a Mode or
        # its hold left out. A change over a window w is that from the
        # bin w before to the bin, counted in the bin's regime.
        class Changes
            # data: { [location, device] => { bin => value } };
            # references: { location => [device] }; timeline: the span's.
            def initialize(setup, data, references, timeline)
                @setup      = setup
                @series     = setup.series
                @data       = data.reject { |(location, _), _| location.nil? }
                @references = references
                @timeline   = timeline
            end

            # [Profile] of every sensor.
            def profiles = @data.keys.flat_map { of(*it) }

            # [Profile] of a sensor, one per regime it has a Threshold in.
            def of(location, device)
                own = thresholds(own(location, device))
                relative = thresholds(relative(location, device))
                (own.keys | relative.keys).map do |regime|
                    Profile.new(location:, device:, regime:,
                                quantity: @setup.quantity.name,
                                own: own.fetch(regime, {}),
                                relative: relative.fetch(regime, {}))
                end
            end

            # The bins where the sensor's relative change over a window
            # is beyond its regime's relative Threshold; profiles:
            # { regime => Profile }.
            def jumps(location, device, profiles)
                series = relative(location, device)
                series.keys.select do |bin|
                    found = profiles[regime_of(bin)]&.relative or next false
                    found.any? do |window, threshold|
                        jump?(series, bin, window, threshold)
                    end
                end
            end

            private

            def jump?(series, bin, window, threshold)
                change = change(series, bin, window) or return false
                !threshold.beyond(change).nil?
            end

            # { regime => { window => Threshold } } of a series, the
            # windows with a Threshold.
            def thresholds(series)
                regimes = series.keys.group_by { regime_of(it) }
                regimes.to_h { |regime, bins| [regime, windows(series, bins)] }
                       .reject { |_, found| found.empty? }
            end

            # { window => Threshold } of the changes ending in the bins.
            def windows(series, bins)
                @setup.transient_windows.filter_map do |window|
                    changes = bins.filter_map { change(series, it, window) }
                    found = Transient.threshold(changes, @setup)
                    [window, found] if found
                end.to_h
            end

            def change(series, bin, window)
                before = series[bin - window] or return
                series[bin] - before
            end

            # { bin => value } of a sensor, carried, a Mode's bins out.
            def own(location, device)
                (@own ||= {})[[location, device]] ||=
                    @series.carried(@data.fetch([location, device], {}),
                                    @setup.carry)
                           .reject { |bin, _| @timeline.near?(location, bin) }
            end

            # { bin => sensor - reference }; none for a reference.
            def relative(location, device)
                devices = @references.fetch(location, [device])
                return {} if devices.include?(device)
                reference = reference(location, devices)
                own(location, device).filter_map do |bin, value|
                    [bin, value - reference[bin]] if reference[bin]
                end.to_h
            end

            def reference(location, devices)
                (@reference ||= {})[location] ||=
                    @series.mean(devices.map { own(location, it) })
            end

            def regime_of(bin)
                (@regimes ||= {})[bin] ||= @setup.regime.of(Time.at(bin))
            end
        end
    end
end
