# frozen_string_literal: true

module Sensorium
    class Fit
        # The Series chosen best-first and fitted together (setup.joint),
        # for a Fit: at each step, each not chosen yet is fitted with
        # those chosen, all of them together on what the model before
        # the Series left (Linear.joint); the one that narrows most is
        # kept as any term is (Fit#better), else the choice ends; it
        # ends too once what is kept brings no new Series. Stepwise, each
        # Series would take what it can of the others' share, in their
        # order: several rooms' valves, open together, would be told
        # apart by the order they were given in.
        module Joint
            private

            def joint(model)
                chosen = model
                loop do
                    tried = (@terms.series.keys - chosen.series.keys)
                            .filter_map { joined(model, chosen, it) }
                    kept = better(chosen, tried.min_by { ratio(chosen, it) })
                    return chosen unless grown?(chosen, kept)
                    chosen = kept
                end
            end

            # Whether kept has a Series chosen lacks: one tried whose
            # slope was held at 0 (Stats.nonnegative) is the model
            # chosen again, its spread the same, and a narrows of 1
            # would keep it for ever.
            def grown?(chosen, kept)
                (kept.series.keys - chosen.series.keys).any?
            end

            # model with the Series chosen so far and name, fitted
            # together.
            def joined(model, chosen, name)
                names = [*chosen.series.keys, name]
                Linear.joint(model, @terms.series.slice(*names), @setup)
            end
        end
    end
end
