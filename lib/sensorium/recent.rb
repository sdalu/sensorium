# frozen_string_literal: true

module Sensorium
    # A sensor's gap to its location's reference as it stood lately: the
    # median of sensor - reference over the bins of the days before `at`
    # on which the Modes held what `holding` names (Recent.named: a
    # Shift's name and value, "-" for none), its p10..p90 and the bins
    # counted (samples), over from..to. For a caller that sends a
    # device the setpoint its own sensor reads at the room's target
    # (README, Predicting): the gap these last days, the valve's duty,
    # the pipe's heat and whatever else moved the sensor included,
    # where an Offset states the season's model and a Track follows it
    # slowly. Not learned, computed when asked: no store keeps it.
    Recent = Data.define(:location, :device, :quantity, :holding, :gap,
                         :p10, :p90, :samples, :from, :to) do
        def sigma = (p90 - p10) / P10_P90

        # The reading expected while the reference is r: r + gap, σ the
        # gap's spread; Offset#predict's counterpart, r taken as exact.
        def predict(r) = Estimate.new(value: r + gap, sigma:)
    end

    class Recent
        DAYS = 3
        MIN  = 50

        # The name of what holds (holding: [[name, value]] of the
        # Modes, as Snapshot#holding gives them): "-" for none, else
        # Shift.named's name and value joined by "=".
        def self.named(holding)
            holding.empty? ? "-" : Shift.named(holding).join("=")
        end

        # [Recent] of every sensor of each location with a reference
        # (as the Learner finds them, locations: as its), one per Mode
        # state seen MIN bins at least over the `days` before `at`, the
        # History over that span read from the source (from).
        def self.learn(source, setup, at:, days: DAYS, locations: {})
            from(History.load(source, setup, from: at - (days * 86_400),
                                             to: at, locations:))
        end

        # [Recent] over a History's span.
        def self.from(history)
            history.references.flat_map do |location, references|
                sensors(history, location, references).flat_map do |device|
                    of(history, location, device)
                end
            end
        end

        # The Recent of a sensor for what holds among `recents`; nil
        # without one.
        def self.find(recents, location, device, holding)
            key = [location, device, named(holding)]
            recents.find { [it.location, it.device, it.holding] == key }
        end

        # The location's sensors that are not its references.
        def self.sensors(history, location, references)
            history.data.keys.filter_map do |where, device|
                device if where == location && !references.include?(device)
            end
        end
        private_class_method :sensors

        # The Recents of one sensor, one per Mode state with MIN bins.
        def self.of(history, location, device)
            gaps(history, location, device).filter_map do |holding, values|
                next if values.size < MIN
                new(location:, device:, quantity: history.quantity, holding:,
                    gap: Stats.median(values),
                    p10: Stats.quantile(values, 0.1),
                    p90: Stats.quantile(values, 0.9), samples: values.size,
                    from: history.from, to: history.to)
            end
        end
        private_class_method :of

        # { holding => [sensor - reference] } over the bins both have.
        def self.gaps(history, location, device)
            reference = history.carried(location)
            pairs = history.data.fetch([location, device], {})
                           .filter_map do |bin, value|
                r = reference[bin] or next
                [named(history.timeline.modes(location, bin)), value - r]
            end
            pairs.group_by(&:first).transform_values { it.map(&:last) }
        end
        private_class_method :gaps
    end
end
