# frozen_string_literal: true

module Sensorium
    module Store
        # Refuses rows of another quantity than the one they are kept
        # under: they would be dropped under one and kept under another.
        def self.same_quantity!(quantity, rows)
            other = rows.map(&:quantity).uniq - [quantity]
            return if other.empty?
            raise ArgumentError, "kept as #{quantity}, but of " \
                                 "#{other.join(", ")}"
        end

        # Refuses tracks ({ key => Track }) of another quantity, or under
        # another key than their own (key: the block giving a track
        # its own): a store would file them under one or the other.
        def self.own_tracks!(quantity, tracks, &key)
            same_quantity!(quantity, tracks.values)
            wrong = tracks.reject { |given, track| key.call(track) == given }
            return if wrong.empty?
            raise ArgumentError, "tracks under another key: " \
                                 "#{wrong.keys.inspect}"
        end

        # What both stores answer alike, from their other methods.
        module Knowing
            # The Knowledge of a quantity: all the store keeps of it.
            def knowledge(quantity)
                Sensorium::Knowledge.new(
                    offsets: offsets(quantity), shifts: shifts(quantity),
                    locations: locations(quantity), tracks: tracks(quantity),
                    dynamics: dynamics(quantity),
                    transients: transients(quantity),
                    collocations: collocations(quantity)
                )
            end
        end
    end
end
