# frozen_string_literal: true

module Sensorium
    # How one quantity is learned and fused:
    #   quantity    the Quantity
    #   regime      Regime::Calendar, Regime::Constant, or any object
    #               answering names, of(time), covered(from, to)
    #   influences  [Influence::Switch, Influence::Mode]
    #   places      tags tried in turn for a location's reference when
    #               none is set ("ceiling", then "floor")
    #   bin         seconds a bin spans
    #   carry       seconds a reading stands for the bins after it
    #   min_samples calm bins a sensor needs in a regime
    #   min_shift   bins a Mode value needs to be learned as a Shift
    #   min_part    bins each side of a Switch needs
    #   narrows     a term is kept when it narrows the spread to this
    #   covers      share of the bins a neighbour must cover
    #   gain        whether a gain term is tried
    Setup = Data.define(:quantity, :regime, :influences, :places, :bin,
                        :carry, :min_samples, :min_shift, :min_part,
                        :narrows, :covers, :gain)

    class Setup
        DEFAULTS = { regime: Regime::Constant.new, influences: [],
                     places: [], bin: 600, carry: 3600, min_samples: 500,
                     min_shift: 100, min_part: 100, narrows: 0.8,
                     covers: 0.8, gain: true }.freeze

        def initialize(quantity:, **settings)
            super(quantity:, **DEFAULTS.merge(settings))
        end

        def switches = influences.grep(Influence::Switch)
        def modes    = influences.grep(Influence::Mode)
        def series   = Series.new(bin)
    end
end
