# frozen_string_literal: true

module Sensorium
    # One sensor's offset from its location's reference, bin by bin
    # (diffs: { bin => sensor - reference }), fitted as a constant, then
    # with each Switch in turn (switches: { name => bins it was on }),
    # then with the linear terms: a gain on the reference's level
    # (levels: { bin => reference }) and the gap to a neighbour
    # (candidates: { name => { bin => reference - neighbour } }), the one
    # that narrows most first, then both together. A term is kept only
    # when it narrows the spread (p10..p90) to setup.narrows of what it
    # was.
    class Fit
        # residuals: { bin => what the model leaves }.
        Model = Data.define(:constant, :switches, :gain, :neighbour,
                            :coefficient, :residuals) do
            def spread = Stats.spread(residuals.values)
        end

        def initialize(diffs, setup, levels:, switches: {}, candidates: {})
            @diffs      = diffs
            @setup      = setup
            @levels     = levels
            @switches   = switches
            @candidates = candidates
        end

        def model
            best = @switches.reduce(plain) do |kept, (name, on)|
                better(kept, switch(kept, name, on))
            end
            linear(best)
        end

        # The constant alone.
        def plain
            @plain ||= begin
                value = Stats.median(@diffs.values)
                Model.new(constant: value, switches: {}, gain: nil,
                          neighbour: nil, coefficient: nil,
                          residuals: @diffs.transform_values { it - value })
            end
        end

        private

        def better(kept, tried)
            return kept unless tried
            tried.spread <= @setup.narrows * kept.spread ? tried : kept
        end

        # The switch's term: the median while on over the median while
        # off, both of what the model left.
        def switch(model, name, on)
            found = term(model.residuals, on) or return
            base, term = found
            model.with(constant: model.constant + base,
                       switches: model.switches.merge(name => term),
                       residuals: switched(model.residuals, on, base, term))
        end

        # [the median while off, while on less it], nil when either
        # side has too few bins.
        def term(residuals, on)
            held, off = residuals.partition { |bin, _| on.include?(bin) }
                                 .map { |part| part.map(&:last) }
            return if [held, off].any? { it.size < @setup.min_part }
            base = Stats.median(off)
            [base, Stats.median(held) - base]
        end

        def switched(residuals, on, base, term)
            residuals.to_h do |bin, r|
                [bin, r - base - (on.include?(bin) ? term : 0.0)]
            end
        end

        def linear(model)
            first = better(model, singles(model).min_by(&:spread))
            return first if first.equal?(model)
            better(first, both(model, first))
        end

        def singles(model)
            gain = Linear.gain(model, @levels, @setup) if @setup.gain
            [gain, *@candidates.map do |name, gaps|
                Linear.neighbour(model, name, gaps, @setup)
            end].compact
        end

        # The gain and a neighbour together, over what model left: the
        # first's neighbour, or the best of them after a gain.
        def both(model, first)
            return unless @setup.gain
            names = first.neighbour ? [first.neighbour] : @candidates.keys
            names.filter_map do |name|
                Linear.both(model, @levels, name, @candidates[name], @setup)
            end.min_by(&:spread)
        end
    end
end

require_relative "fit/linear"
