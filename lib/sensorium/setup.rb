# frozen_string_literal: true

module Sensorium
    # How one quantity is learned and fused:
    #   quantity    the Quantity
    #   regime      Regime::Calendar, Regime::Constant, or any object
    #               answering names, of(time), covered(from, to)
    #   influences  [Influence::Switch, Influence::Mode,
    #               Influence::Series, Influence::Threshold,
    #               Influence::Transient]
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
    #   rate        whether a term on the reference's rate (dr/dt) is
    #               tried
    #   outside     the external series (a device of the source's
    #               externals) a location's Dynamics follow; nil, none
    #   dynamics_margin  a Dynamics model is kept when its error, held
    #               out, is at most this share of holding the value's
    #   scale_floor a linear term is refused when it leaves |1 + gain +
    #               coefficient| below this: a correction divides by it
    #   transient_windows  seconds over which a sensor's change is
    #               measured against its Transient::Profile
    #   transient_z a change is a transient when its z is at least this
    #               in size
    Setup = Data.define(:quantity, :regime, :influences, :places, :bin,
                        :carry, :min_samples, :min_shift, :min_part,
                        :narrows, :covers, :gain, :rate, :outside,
                        :dynamics_margin, :scale_floor, :transient_windows,
                        :transient_z)

    class Setup
        DEFAULTS = { regime: Regime::Constant.new, influences: [],
                     places: [], bin: 600, carry: 3600, min_samples: 500,
                     min_shift: 100, min_part: 100, narrows: 0.8,
                     covers: 0.8, gain: true, rate: true,
                     outside: nil, dynamics_margin: 0.98,
                     scale_floor: 0.5, transient_windows: [600, 1200],
                     transient_z: 5 }.freeze

        def initialize(quantity:, **settings)
            super(quantity:, **DEFAULTS.merge(settings))
        end

        def switches   = influences.grep(Influence::Switch)
        def modes      = influences.grep(Influence::Mode)
        def levels     = influences.grep(Influence::Series)
        def thresholds = influences.grep(Influence::Threshold)
        def transients = influences.grep(Influence::Transient)
        def series     = Series.new(bin)
    end
end
