# frozen_string_literal: true

module Sensorium
    module Store
        class Sequel
            module Schema
                # A table's generator, its columns renamed.
                class Renamed
                    TYPES = %i[String Float Integer Time].freeze

                    def initialize(generator, columns)
                        @generator = generator
                        @columns   = columns
                    end

                    TYPES.each do |type|
                        define_method(type) do |name, **options|
                            @generator.public_send(type, rename(name),
                                                   **options)
                        end
                    end

                    def primary_key(names)
                        @generator.primary_key(names.map { rename(it) })
                    end

                    private

                    def rename(name) = @columns.fetch(name, name)
                end

                # The column names a table's definition gives.
                class Names
                    # The store's own column names, of every table.
                    def self.all
                        @all ||= begin
                            names = new
                            Schema::TABLES.each { Schema.public_send(it, names) }
                            names.to_a.uniq.freeze
                        end
                    end

                    def to_a = @to_a ||= []

                    Renamed::TYPES.each do |type|
                        define_method(type) { |name, **| to_a << name }
                    end

                    def primary_key(_names) = nil
                end
            end
        end
    end
end
