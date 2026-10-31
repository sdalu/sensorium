# frozen_string_literal: true

module Sensorium
    # Setups for the rooms of a house, as first measured in one (winter
    # 2025-26): calendar seasons; the radiators' water ("heating",
    # house-wide, an hour after a valve opened) and the aircon
    # ("aircon", per room, half an hour after a run); for humidity, the
    # creep of a sensor for six hours after its room's reference read
    # above 80 % ("creep"); for both, the transients ("transient", a
    # sensor moving apart from its reference, and 30 minutes after,
    # left out). The temperature's
    # reference is a smoke detector on the ceiling, else a leak sensor
    # on the floor; neither measures humidity, whose reference is a
    # wall unit (an aircon's), else a radiator valve's. The source tells
    # the events under those names, and tags the sensors "ceiling",
    # "floor", "wall" and "valve".
    module Presets
        TEMPERATURE = Quantity.new(name: "temperature", unit: "°C",
                                   sigma: 0.1, drift: 1.0)

        # Fused as absolute humidity (g/m³); a reading needs its sensor's
        # temperature (context[:temperature]). σ 0.3 g/m³ is about 2 %
        # at 20 °C. A shower moves it by several g/m³ in minutes: set a
        # wider drift on those rooms' Location.
        HUMIDITY = Quantity.new(name: "humidity", unit: "%", sigma: 0.3,
                                drift: 0.5, max_age: 120,
                                transform: Transform::AbsoluteHumidity)

        PLACES = { "temperature" => %w[ceiling floor],
                   "humidity" => %w[wall valve] }.freeze

        HEATING = Influence::Switch.new(name: "heating", scope: :site,
                                        hold: 3600)
        AIRCON  = Influence::Mode.new(name: "aircon", scope: :location,
                                      hold: 1800)

        CREEP = Influence::Threshold.new(name: "creep", above: 80,
                                         hold: 6 * 3600)

        TRANSIENT = Influence::Transient.new

        INFLUENCES = { "humidity" => [HEATING, AIRCON, CREEP, TRANSIENT] }
                     .freeze

        module_function

        def room(quantity = TEMPERATURE, **settings)
            Setup.new(quantity:, regime: Regime::Calendar.new,
                      influences: INFLUENCES.fetch(quantity.name,
                                                   [HEATING, AIRCON,
                                                    TRANSIENT]),
                      places: PLACES.fetch(quantity.name, []), **settings)
        end
    end
end
