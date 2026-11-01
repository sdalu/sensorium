# frozen_string_literal: true

module Sensorium
    # Each series' own error at a location, in a regime, by triple
    # collocation: the reference and its sensors corrected to it (by
    # their Offsets), over the calm bins where all have a value, the
    # error variance of series i is the mean, over the pairs (j, k) of
    # the others, of cov(x_i - x_j, x_i - x_k). It needs three series
    # at least and assumes their errors independent: an error every
    # series shares cannot be seen. sigmas: { device => σ }, the
    # reference under its name ("a+b" for a mean); nil where the
    # estimate came out negative (not measurable); samples: the bins
    # it was found over.
    Collocation = Data.define(:location, :quantity, :regime, :sigmas,
                              :samples) do
        def initialize(sigmas:, **)
            super(sigmas: sigmas.transform_keys(&:to_s), **)
        end

        # A device's σ, nil when not measurable or not collocated.
        def sigma(device) = sigmas[device.to_s]
    end

    class Collocation
        # [Collocation] of each location and regime with three series
        # or more seen together setup.min_samples calm bins at least,
        # its sensors corrected with `offsets` ([Offset], those against
        # the location's reference count). span: from:, to: and
        # locations: ({ name => Location }, those set), as the
        # Learner's, the History loaded from the source when none is
        # given.
        def self.learn(source, setup, offsets:, history: nil, **span)
            history ||= History.load(source, setup, **span)
            Gather.new(history).collocations(offsets)
        end

        # { name => σ, nil when not measurable } of aligned columns
        # { name => [value] }.
        def self.sigmas(columns)
            columns.keys.to_h do |name|
                variance = variance(columns, name)
                [name, variance.negative? ? nil : Math.sqrt(variance)]
            end
        end

        # The mean over the pairs (j, k) of the others of
        # cov(x_i - x_j, x_i - x_k).
        def self.variance(columns, name)
            pairs = (columns.keys - [name]).combination(2).to_a
            pairs.sum do |j, k|
                Stats.covariance(apart(columns, name, j),
                                 apart(columns, name, k))
            end / pairs.size
        end

        def self.apart(columns, name, other)
            columns[name].zip(columns[other]).map { |x, y| x - y }
        end
    end
end

require_relative "collocation/gather"
