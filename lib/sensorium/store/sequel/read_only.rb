# frozen_string_literal: true

module Sensorium
    module Store
        # What a store opened read-only raises on a write.
        class ReadOnlyError < StandardError; end

        class Sequel
            # A store opened read_only: true: every method that writes
            # raises ReadOnlyError before it reaches the database. The
            # database's own grants (a SELECT-only user) are the guard;
            # this says so at the call, by name.
            module ReadOnly
                WRITES = %i[keep set_location forget keep_tracks
                            keep_dynamics keep_collocations
                            keep_transients].freeze

                WRITES.each do |name|
                    define_method(name) do |*|
                        raise ReadOnlyError, "#{name}: the store is read-only"
                    end
                end
            end
        end
    end
end
