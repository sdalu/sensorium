# frozen_string_literal: true

module Sensorium
    class Fit
        # Whether a Fit keeps a term: tried, the model with it, over
        # kept, the one without.
        module Keep
            private

            def better(kept, tried)
                return kept unless tried && narrows?(kept, tried)
                return kept if @held_out && !@held_out.keeps?(kept, tried)
                tried
            end

            # Whether tried narrows what kept left to setup.narrows.
            def narrows?(kept, tried)
                narrowing(kept, tried) <= @setup.narrows
            end

            # The spread tried leaves over what kept left, as the
            # correction's (over each model's scale), the bins the term
            # acts on weighing as much as the others (Balanced):
            # infinite when it acts on fewer than setup.min_part.
            def narrowing(kept, tried)
                found = Balanced.ratio(kept.residuals, tried.residuals,
                                       @setup.min_part,
                                       Balanced.regressor(kept, tried,
                                                          @terms)) or
                    return Float::INFINITY
                found * kept.scale / tried.scale
            end
        end
    end
end
