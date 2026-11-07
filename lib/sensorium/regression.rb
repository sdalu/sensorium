# frozen_string_literal: true

module Sensorium
    # A quantity explained by regressors, in a regime:
    #   value = constant + Σ terms[name] × (that regressor's value)
    # a regressor kept only when it narrowed the spread of what the
    # model leaves, as an Offset's terms are (Fit), and confirmed on the
    # bins held out (Fit::Validated); p10..p90 is what the model leaves,
    # widened by as much as the bins held out confirmed less. plain is
    # the median alone and plain_p10..plain_p90 its spread, the fallback
    # when a regressor's value is not known. block_share as an Offset's,
    # for the Tracker's CUSUM (follow). The house's gas a day, explained
    # by each room's valve: constant is what no valve explains, and
    # terms[room] × that room's valve the room's share (contributions).
    # An Offset is the case where the value is a sensor's gap to its
    # reference, with terms of its own (a gain on the reference, a
    # neighbour); a Regression has none of those, and keeps its terms
    # by name.
    Regression = Data.define(:name, :quantity, :regime, :constant, :terms,
                             :p10, :p90, :samples, :plain, :plain_p10,
                             :plain_p90, :block_share) do
        def initialize(block_share: nil, **given)
            super(**given, block_share:,
                           terms: given[:terms].transform_keys(&:to_s))
        end

        def sigma       = (p90 - p10) / P10_P90
        def plain_sigma = (plain_p90 - plain_p10) / P10_P90

        # The value expected given the regressors' values ({ name =>
        # value }), with its σ: the model, or the plain median when one
        # of its regressors' values is not known (nil or absent). With a
        # track (follow), as it says the value runs now: its delta put
        # back, its variance added (Track#foresee); nil while it is
        # jumped.
        def predict(values = {}, track: nil)
            values = values.transform_keys(&:to_s)
            found = if known?(values)
                        Estimate.new(value: constant + parts(values), sigma:)
                    else
                        Estimate.new(value: plain, sigma: plain_sigma)
                    end
            track ? track.foresee(found) : found
        end

        # { name => term × value } of each regressor: its share of the
        # value predicted, the constant aside. Every regressor's value
        # is needed (KeyError otherwise). A name is a String, a Symbol
        # given taken as its String, as everywhere.
        def contributions(values)
            values = values.transform_keys(&:to_s)
            terms.to_h { |name, term| [name, term * values.fetch(name)] }
        end

        # Whether every regressor's value is known.
        def known?(values)
            values = values.transform_keys(&:to_s)
            terms.each_key.all? { !values[it].nil? }
        end

        private

        def parts(values) = contributions(values).values.sum
    end
end

require_relative "regression/learner"
require_relative "regression/inputs"
require_relative "regression/tracking"
