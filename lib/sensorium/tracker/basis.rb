# frozen_string_literal: true

module Sensorium
    class Tracker
        # What each part is tracked by: its Track, the σ its drift is
        # measured in, and the share its block means are standardised
        # by.
        module Basis
            private

            # { device => [Track, σ, share, width] } of the parts tracked:
            # theirs while it has the fingerprint of the moment, else a
            # fresh one; σ, what their drift is measured in, nil for a
            # reference; share, what their block means are standardised
            # by; width, what a reference's innovations are judged with
            # at least (nil for another part: its own σ).
            def current(tracks, fused, parts)
                parts.filter_map do |part|
                    found = basis(fused, part.device) or next
                    fresh, *rest = found
                    track = tracks[[fused.location, part.device]]
                    track = fresh unless track&.fingerprint == fresh.fingerprint
                    [part.device, [track, *rest]]
                end.to_h
            end

            # A fresh Track of the device, the σ its drift is measured in,
            # its block share and the width its innovations are judged
            # with: a reference's, without σ (it never drifts), with the
            # largest share of the location's Offsets (its innovations are
            # against the same others) and the smallest of their σ (the
            # reference's disagreement with the room is in every Offset's
            # σ, and the tightest bounds it: the quantity's σ is the
            # instrument's own error, not its excursions); another's, of
            # its Offset learned against the Fused's references, with its
            # σ and share, no width; nil without.
            def basis(fused, device)
                if references_of(fused).include?(device)
                    learned = offsets_of(fused)
                    [reference(fused, device), nil,
                     learned.filter_map(&:block_share).max,
                     learned.map(&:sigma).min]
                elsif (offset = offset(fused, device))
                    [Track.fresh(offset, variance), offset.sigma,
                     offset.block_share, nil]
                end
            end

            # The Offsets of the Fused's location, regime and references.
            def offsets_of(fused)
                @offsets.each_value.select do |offset|
                    offset.location == fused.location &&
                        offset.regime == regime(fused) &&
                        offset.reference == fused.reference
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
