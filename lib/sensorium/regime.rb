# frozen_string_literal: true

require "date"

module Sensorium
    # How the history is cut into spans learned apart: what influences a
    # sensor may differ from one regime to the next (the radiators in
    # winter, the aircon in summer). A regime answers names, of(time) and
    # covered(from, to); of is asked of local times.
    module Regime
        # By month: winter Nov–Mar, mid Apr, May, Oct, summer Jun–Sep by
        # default.
        class Calendar
            SEASONS = { "winter" => [11, 12, 1, 2, 3],
                        "mid" => [4, 5, 10],
                        "summer" => [6, 7, 8, 9] }.freeze

            attr_reader :names

            # months: { name => [month] }, every month in one of them.
            def initialize(months = SEASONS)
                @months   = months.transform_keys(&:to_s)
                @names    = @months.keys.freeze
                @by_month = @months.flat_map do |name, list|
                    list.map { [it, name] }
                end.to_h
            end

            # The months are the site's, in the local zone whatever the
            # time's own (a History's bins are local, a Store's times UTC).
            def of(time) = @by_month.fetch(time.getlocal.month)

            # The regimes a span of time touches, in names' order.
            def covered(from, to)
                months = (from.getlocal.to_date..to.getlocal.to_date)
                         .map(&:month).uniq
                @names.select { @months[it].intersect?(months) }
            end
        end

        # One regime throughout.
        class Constant
            attr_reader :names

            def initialize(name = "all") = @names = [name.to_s].freeze

            def of(_time)             = @names.first
            def covered(_from, _to)   = @names
        end
    end
end
