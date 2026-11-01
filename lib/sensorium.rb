# frozen_string_literal: true

# Sensors of one quantity that share a location rarely agree: each is
# biased by where it sits and by what runs near it. Sensorium learns,
# from their history, how each one reads against the location's
# reference (Learner), corrects each reading back to that reference
# (Offset#correct), and fuses them into one value with its uncertainty
# (Fusion). What the quantity is, how the history is cut into regimes,
# and what influences the sensors is told by a Setup.
module Sensorium
    # σ from a p10..p90 width, as for a normal distribution.
    P10_P90 = 2.563

    # A sensor's reading. context: what the transform needs besides the
    # value, by name (a humidity sensor's own temperature).
    Reading = Data.define(:time, :location, :device, :value, :context) do
        def initialize(context: {}, **) = super
    end

    # A sensor and where it sits. tags: what the reference policy picks
    # by ("ceiling", "floor"); neighbour: whether the other locations may
    # be learned against it.
    Sensor = Data.define(:name, :location, :tags, :neighbour) do
        def initialize(tags: [], neighbour: true, **)
            super(tags: Array(tags).map(&:to_s), neighbour:, **)
        end
    end

    # A value and how far it can be trusted (one σ).
    Estimate = Data.define(:value, :sigma)

    class Error < StandardError; end

    # A location's references named as one, "a+b" for the mean of a and
    # b, each device's "%" and "+" escaped (%25, %2B) so that a device
    # named with a "+" stays one.
    def self.reference_name(devices)
        devices.map { it.to_s.gsub("%", "%25").gsub("+", "%2B") }.join("+")
    end

    # The devices a reference name was made of.
    def self.references_of(name)
        name.split("+").map { it.gsub("%2B", "+").gsub("%25", "%") }
    end
end

require_relative "sensorium/version"
require_relative "sensorium/stats"
require_relative "sensorium/series"
require_relative "sensorium/regime"
require_relative "sensorium/influence"
require_relative "sensorium/transform"
require_relative "sensorium/quantity"
require_relative "sensorium/location"
require_relative "sensorium/setup"
require_relative "sensorium/shift"
require_relative "sensorium/offset"
require_relative "sensorium/fit"
require_relative "sensorium/timeline"
require_relative "sensorium/learned"
require_relative "sensorium/learner"
require_relative "sensorium/dynamics"
require_relative "sensorium/collocation"
require_relative "sensorium/transient"
require_relative "sensorium/history"
require_relative "sensorium/snapshot"
require_relative "sensorium/parts"
require_relative "sensorium/combine"
require_relative "sensorium/fusion"
require_relative "sensorium/blend"
require_relative "sensorium/tracker"
require_relative "sensorium/store/memory"
require_relative "sensorium/presets"
