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
    #   min_samples calm bins a sensor needs in a regime (500 of ten
    #               minutes; by default the same time with another bin)
    #   min_shift   bins a Mode value needs to be learned as a Shift (100,
    #               likewise)
    #   min_part    bins each side of a Switch needs (100, likewise), and
    #               the fewest an offset's terms are held out on
    #               (Fit::Validated)
    #   narrows     a term is kept when it narrows the correction's
    #               spread to this
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
    #               measured against its Transient::Profile, whole bins
    #               (one bin and two by default)
    #   transient_rate  false alarms a day a sensor's thresholds allow,
    #               per window and direction: each is the quantile of its
    #               calm changes at 1 - rate / bins a day
    Setup = Data.define(:quantity, :regime, :influences, :places, :bin,
                        :carry, :min_samples, :min_shift, :min_part,
                        :narrows, :covers, :gain, :rate, :outside,
                        :dynamics_margin, :scale_floor, :transient_windows,
                        :transient_rate)

    class Setup
        DEFAULTS = { regime: Regime::Constant.new, influences: [],
                     places: [], bin: 600, carry: 3600, min_samples: 500,
                     min_shift: 100, min_part: 100, narrows: 0.8,
                     covers: 0.8, gain: true, rate: true,
                     outside: nil, dynamics_margin: 0.98,
                     scale_floor: 0.5, transient_windows: [600, 1200],
                     transient_rate: 0.2 }.freeze

        # The bin DEFAULTS' counts (min_samples, min_shift, min_part) are
        # for; with another bin they cover the same time, and the
        # transient windows are one bin and two unless given.
        BIN    = 600
        COUNTS = %i[min_samples min_shift min_part].freeze

        def initialize(quantity:, **settings)
            bin = settings.fetch(:bin, BIN)
            unless bin.is_a?(Integer) && bin.positive?
                raise ArgumentError, "bin: #{bin.inspect}, not whole seconds"
            end
            given = Setup.defaults(bin).merge(settings)
            Setup.check_windows(given[:transient_windows], bin)
            @given = { quantity:, **settings }
            super(quantity:, **given)
        end

        # The Setup with changes, the counts and transient windows
        # derived again from bin unless they were set.
        def with(**changes)
            changes.empty? ? self : self.class.new(**@given, **changes)
        end

        def self.defaults(bin)
            DEFAULTS.merge(
                COUNTS.to_h { [it, (DEFAULTS[it] * BIN / bin.to_f).round] },
                transient_windows: [bin, 2 * bin]
            )
        end

        # A window not a whole number of bins would find no bin to start
        # its change from.
        def self.check_windows(windows, bin)
            wrong = windows.reject { it.positive? && (it % bin).zero? }
            return if wrong.empty?
            raise ArgumentError, "transient_windows #{wrong.inspect}: " \
                                 "not whole bins of #{bin} s"
        end

        def switches   = influences.grep(Influence::Switch)
        def modes      = influences.grep(Influence::Mode)
        def levels     = influences.grep(Influence::Series)
        def thresholds = influences.grep(Influence::Threshold)
        def transients = influences.grep(Influence::Transient)
        def series     = Series.new(bin)
    end
end
