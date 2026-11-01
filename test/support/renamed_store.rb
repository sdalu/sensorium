# frozen_string_literal: true

require "sensorium/store/sequel"

# A Store::Sequel over tables whose key columns and times have other
# names, as a caller's own schema may have them.
module RenamedStore
    COLUMNS = { location: :zone, device: :sensor, quantity: :kind,
                regime: :season, learned_from: :span_from,
                learned_to: :span_to, learned_at: :made_at,
                tracked_at: :seen_at }.freeze

    def self.new(db = Sequel.sqlite)
        Sensorium::Store::Sequel.new(db, columns: COLUMNS)
    end
end
