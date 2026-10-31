# frozen_string_literal: true

module Sensorium
    # Several estimates made one, each weighted: { key => estimate },
    # an estimate anything answering value and sigma (an Estimate, a
    # Fusion::Fused, a Blend::Blended…), its key whatever the caller
    # names it by (a location, a floor, a sensor). The weights are the
    # caller's: how occupied a room is, its floor area, a priority. An
    # estimate without weight, or without a value, does not count, the
    # others' shares filling its place. σ² = Σ (w / W)² σ², the errors
    # taken as independent; nil when one that counts has none. With no
    # weight anywhere, no value: the caller chooses what stands in.
    # Estimates that say their quantity must say the same one.
    class Blend
        # shares: { key => Share }, every key given, its share of the
        # value (0..1); quantity and at: the estimates' when they say
        # them (at, the latest), else nil.
        Blended = Data.define(:value, :sigma, :shares, :quantity, :at)
        Share   = Data.define(:weight, :value, :sigma)

        # weights: { key => weight >= 0 }, missing keys 0; or anything
        # answering call(key) with one.
        def initialize(weights)
            @weights = weights.respond_to?(:call) ? weights : table(weights)
        end

        def of(estimates)
            weights = estimates.to_h { |key, one| [key, weight(key, one)] }
            counted = weights.select { |_, w| w.positive? }.keys
            total = counted.sum { weights[it] }.to_f
            Blended.new(**sum(estimates, weights, counted, total),
                        shares: shares(estimates, weights, total),
                        **said(estimates.values))
        end

        private

        def table(weights)
            all = weights.to_h
            ->(key) { all.fetch(key, 0) }
        end

        # A key's weight, 0 for an estimate without a value.
        def weight(key, estimate)
            weight = @weights.call(key).to_f
            if weight.negative?
                raise ArgumentError,
                      "a weight below zero: #{key}"
            end
            estimate.value.nil? ? 0.0 : weight
        end

        def sum(estimates, weights, counted, total)
            return { value: nil, sigma: nil } if counted.empty?
            items = counted.map { [weights[it] / total, estimates[it]] }
            { value: items.sum { |share, one| share * one.value },
              sigma: spread(items) }
        end

        def spread(items)
            return if items.any? { |_, one| one.sigma.nil? }
            Math.sqrt(items.sum { |share, one| (share * one.sigma)**2 })
        end

        def shares(estimates, weights, total)
            estimates.to_h do |key, one|
                share = total.positive? ? weights[key] / total : 0.0
                [key, Share.new(weight: share, value: one.value,
                                sigma: one.sigma)]
            end
        end

        # The quantity and the latest moment the estimates say.
        def said(estimates)
            names = estimates.filter_map do |one|
                one.quantity if one.respond_to?(:quantity)
            end.uniq
            raise ArgumentError, "quantities mixed" if names.size > 1
            times = estimates.filter_map { it.at if it.respond_to?(:at) }
            { quantity: names.first, at: times.max }
        end
    end
end
