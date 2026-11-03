# frozen_string_literal: true

module Sensorium
    # What a Mode does to a sensor while it holds one value (the aircon
    # "cooling"), in a regime: a shift on top of its plain offset, and
    # the width it reads within.
    Shift = Data.define(:location, :device, :quantity, :regime, :influence,
                        :mode, :shift, :p10, :p90, :samples) do
        def sigma = (p90 - p10) / P10_P90
    end

    class Shift
        # [influence, mode] of what holds ([[name, value]]): a Mode's name
        # and value; of several at once, their names joined by "+" in
        # names' order, and their values alike ("aircon+fan",
        # "cooling+on"): what two do together is a value of its own.
        def self.named(holding)
            holding.sort.transpose.map { it.join("+") }
        end
    end
end
