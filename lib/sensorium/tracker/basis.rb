# frozen_string_literal: true

module Sensorium
    class Tracker
        # What each part is tracked by: its Track, the σ its drift is
        # measured in, and the share its block means are standardised
        # by.
        module Basis
            private

            # { device => [Track, σ, share] } of the parts tracked: theirs
            # while it has the fingerprint of the moment, else a fresh one;
            # σ, what their drift is measured in, nil for a reference; share,
            # what their block means are standardised by.
            def current(tracks, fused, parts)
                parts.filter_map do |part|
                    found = basis(fused, part.device) or next
                    fresh, *rest = found
                    track = tracks[[fused.location, part.device]]
                    track = fresh unless track&.fingerprint == fresh.fingerprint
                    [part.device, [track, *rest]]
                end.to_h
            end

            # A fresh Track of the device, the σ its drift is measured in and
            # its block share: a reference's, without σ (it never drifts),
            # with the largest share of the location's Offsets (its
            # innovations are against the same others); another's, of its
            # Offset learned against the Fused's references, with its σ and
            # share; nil without.
            def basis(fused, device)
                if references_of(fused).include?(device)
                    [reference(fused, device), nil, shares(fused).max]
                elsif (offset = offset(fused, device))
                    [Track.fresh(offset, variance), offset.sigma,
                     offset.block_share]
                end
            end

            # The block shares of the Offsets of the Fused's location, regime
            # and references.
            def shares(fused)
                @offsets.each_value.filter_map do |offset|
                    next unless offset.location == fused.location &&
                                offset.regime == regime(fused) &&
                                offset.reference == fused.reference
                    offset.block_share
                end
            end

            def reference(fused, device)
                Track.start(location: fused.location, device:,
                            quantity: fused.quantity, regime: regime(fused),
                            reference: fused.reference, variance:)
            end

            def offset(fused, device)
                offset = @offsets[[fused.location, regime(fused), device]]
                offset if offset&.reference == fused.reference
            end

            def regime(fused) = @setup.regime.of(fused.at)

            # A fresh track's: (σ/2)², σ the quantity's.
            def variance = (@quantity.sigma / 2.0)**2
        end

        include Basis
    end
end
