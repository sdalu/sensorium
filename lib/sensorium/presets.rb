# frozen_string_literal: true

module Sensorium
    # Setups for the rooms of a house, as first measured in one (winter
    # 2025-26): calendar seasons; a smoke detector on the ceiling is the
    # reference, else a leak sensor on the floor; the radiators' water
    # ("heating", house-wide, an hour after a valve opened) and the
    # aircon ("aircon", per room, half an hour after a run). The source
    # tells the events under those names, and tags the sensors
    # "ceiling" and "floor".
    module Presets
        TEMPERATURE = Quantity.new(name: "temperature", unit: "°C",
                                   sigma: 0.1, drift: 1.0)

        # Fused as absolute humidity (g/m³); a reading needs its sensor's
        # temperature (context[:temperature]). σ 0.3 g/m³ is about 2 %
        # at 20 °C. HomeKit humidity comes about hourly, hence max_age.
        HUMIDITY = Quantity.new(name: "humidity", unit: "%", sigma: 0.3,
                                drift: 0.5, max_age: 120,
                                transform: Transform::AbsoluteHumidity)

        HEATING = Influence::Switch.new(name: "heating", scope: :site,
                                        hold: 3600)
        AIRCON  = Influence::Mode.new(name: "aircon", scope: :location,
                                      hold: 1800)

        module_function

        def room(quantity = TEMPERATURE, **settings)
            Setup.new(quantity:, regime: Regime::Calendar.new,
                      influences: [HEATING, AIRCON],
                      places: %w[ceiling floor], **settings)
        end
    end
end
