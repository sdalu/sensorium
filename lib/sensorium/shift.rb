# frozen_string_literal: true

module Sensorium
    # What a Mode does to a sensor while it holds one value (the aircon
    # "cooling"), in a regime: a shift on top of its plain offset, and
    # the width it reads within.
    Shift = Data.define(:location, :device, :quantity, :regime, :influence,
                        :mode, :shift, :p10, :p90, :samples) do
        def sigma = (p90 - p10) / P10_P90
    end
end
