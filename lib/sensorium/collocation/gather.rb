# frozen_string_literal: true

module Sensorium
    class Collocation
        # The series a Collocation is found over, read as the Learner
        # reads them: per location and regime, the reference's carried
        # series over the calm bins (no Mode held, nor within its hold)
        # and each sensor's binned values there, corrected by its Offset
        # with what held at each bin (Collocation::Moments).
        class Gather < Learner
            def collocations(offsets)
                sensors = @source.sensors(quantity)
                load(sensors)
                @references = References.new(sensors, @locations,
                                             @setup).all
                offsets.group_by { [it.location, it.regime] }
                       .filter_map { |key, list| collocated(*key, list) }
            end

            private

            def collocated(location, regime, offsets)
                devices = @references[location] or return
                name = Sensorium.reference_name(devices)
                columns = columns(location, regime, name, offsets) or return
                sigmas = Collocation.sigmas(columns)
                                    .transform_values { it&.round(4) }
                Collocation.new(location:, quantity:, regime:, sigmas:,
                                samples: columns.first.last.size)
            end

            # { name => [value] } over the bins all have, nil when fewer
            # than three series or setup.min_samples bins.
            def columns(location, regime, name, offsets)
                reference = calm(location, regime)
                all = { name => reference }
                offsets.each do |offset|
                    next unless offset.reference == name
                    all[offset.device] = corrected(offset, reference)
                end
                aligned(all)
            end

            def aligned(all)
                return if all.size < 3
                bins = all.values.map(&:keys).reduce(:&)
                return if bins.size < @setup.min_samples
                all.transform_values { |series| bins.map { series[it] } }
            end

            # The reference's carried series over the regime's calm bins.
            def calm(location, regime)
                carried(location).select do |bin, _|
                    regime_of(bin) == regime &&
                        !@timeline.near?(location, bin)
                end
            end

            # { bin => the reading corrected } where the reference is.
            def corrected(offset, reference)
                moments = moments(offset.location)
                @data.fetch([offset.location, offset.device], {})
                     .filter_map do |bin, value|
                         next unless reference.key?(bin)
                         [bin, offset.correct(value,
                                              **moments.at(offset, bin))
                                     .value]
                     end.to_h
            end

            def moments(location)
                (@moments ||= {})[location] ||= Moments.new(
                    location, @timeline,
                    reference: carried(location), rates: rates(location),
                    switched: switched(location),
                    gaps: @neighbours.gaps(location, carried(location))
                )
            end

            # { name => bins on } of the Switches (their hard hold) and
            # the Thresholds.
            def switched(location)
                @timeline.switched(location)
                         .merge(@thresholds.of(location,
                                               @references[location]))
            end
        end
    end
end

require_relative "moments"
