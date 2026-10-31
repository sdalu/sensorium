# frozen_string_literal: true

module Sensorium
    # One sensor's offset from its location's reference, bin by bin
    # (diffs: { bin => sensor - reference }), fitted as a constant, then
    # with each Switch in turn (switches: { name => bins it was on }),
    # then each filtered Switch (filtered: { name => { tau => { bin =>
    # exposure } } }) as term × exposure, with the tau that narrows
    # most, then each Series (series: { name => { bin => value } }) as
    # coefficient × value, then with the linear terms: a gain on the
    # reference's level (levels: { bin => reference }) and the gap to a
    # neighbour
    # (candidates: { name => { bin => reference - neighbour } }), the one
    # that narrows most first, then both together, then a term on the
    # reference's rate (rates: { bin => dr/dt per hour }). A term is kept
    # only when it narrows the spread (p10..p90) to setup.narrows of what
    # it was; a linear term, or pair, only when it leaves |1 + gain +
    # coefficient| at setup.scale_floor at least, else the model before
    # it is kept. The terms kept are then refitted together, once
    # (Joint).
    class Fit
        # residuals: { bin => what the model leaves }.
        Model = Data.define(:constant, :switches, :taus, :series, :gain,
                            :neighbour, :coefficient, :rate,
                            :residuals) do
            def spread = Stats.spread(residuals.values)
        end

        # What a model may be fitted with besides the reference's level,
        # each optional (described above).
        # held: { name => bins it was on } of the filtered Switches, their
        # hard hold, for the spreads per state.
        Terms = Data.define(:switches, :filtered, :series, :candidates,
                            :rates, :held) do
            def initialize(switches: {}, filtered: {}, series: {},
                           candidates: {}, rates: nil, held: {})
                super
            end
        end

        def initialize(diffs, setup, levels:, **terms)
            @diffs  = diffs
            @setup  = setup
            @levels = levels
            @terms  = Terms.new(**terms)
        end

        def model
            best = @terms.switches.reduce(plain) do |kept, (name, on)|
                better(kept, Median.switch(kept, name, on, @setup))
            end
            best = @terms.filtered.reduce(best) do |kept, (name, by_tau)|
                better(kept, filtered(kept, name, by_tau))
            end
            Joint.new(@diffs, @setup, @levels, @terms)
                 .of(rated(linear(series(best))))
        end

        # { states:, off_p10:, off_p90: } of a model (Offset): what it
        # leaves while each of its Switches was on, and while all were
        # off, each over setup.min_part bins at least.
        def states(model)
            States.of(model, @terms.held.merge(@terms.switches),
                      @setup.min_part)
        end

        # The constant alone.
        def plain
            @plain ||= begin
                value = Stats.median(@diffs.values)
                Model.new(constant: value, switches: {}, taus: {},
                          series: {}, gain: nil,
                          neighbour: nil, coefficient: nil, rate: nil,
                          residuals: @diffs.transform_values { it - value })
            end
        end

        private

        def better(kept, tried)
            return kept unless tried
            ratio(kept, tried) <= @setup.narrows ? tried : kept
        end

        # The spread tried leaves over what kept left, both over the bins
        # tried covers (a neighbour may cover fewer): infinite when kept
        # left nothing to narrow there.
        def ratio(kept, tried)
            bins = tried.residuals.keys
            before = Stats.spread(kept.residuals.values_at(*bins))
            return Float::INFINITY unless before.positive?
            tried.spread / before
        end

        def linear(model)
            first = better(model, scaled(singles(model)
                                             .min_by { ratio(model, it) }))
            return first if first.equal?(model)
            better(first, scaled(both(model, first)))
        end

        # The model tried, nil when what r is multiplied by, solved for,
        # falls below the scale floor.
        def scaled(tried)
            return unless tried
            scale = 1 + (tried.gain || 0.0) + (tried.coefficient || 0.0)
            tried if scale.abs >= @setup.scale_floor
        end

        # The filtered Switch with the time constant that narrows most.
        def filtered(model, name, by_tau)
            tried = by_tau.filter_map do |tau, exposures|
                Linear.exposure(model, name, tau, exposures, @setup)
            end
            tried.min_by { ratio(model, it) }
        end

        def series(model)
            @terms.series.reduce(model) do |kept, (name, values)|
                better(kept, Linear.series(kept, name, values, @setup))
            end
        end

        def rated(model)
            return model unless @setup.rate && @terms.rates
            better(model, Linear.rate(model, @terms.rates, @setup))
        end

        def singles(model)
            gain = Linear.gain(model, @levels, @setup) if @setup.gain
            [gain, *@terms.candidates.map do |name, gaps|
                Linear.neighbour(model, name, gaps, @setup)
            end].compact
        end

        # The gain and a neighbour together, over what model left: the
        # first's neighbour, or the best of them after a gain.
        def both(model, first)
            return unless @setup.gain
            all = @terms.candidates
            names = first.neighbour ? [first.neighbour] : all.keys
            pairs = names.filter_map do |name|
                Linear.both(model, @levels, name, all[name], @setup)
            end
            pairs.min_by { ratio(first, it) }
        end
    end
end

require_relative "fit/joint"
require_relative "fit/linear"
require_relative "fit/median"
require_relative "fit/states"
