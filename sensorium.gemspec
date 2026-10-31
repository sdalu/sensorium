# frozen_string_literal: true

require_relative "lib/sensorium/version"

Gem::Specification.new do |s|
    s.name        = "sensorium"
    s.version     = Sensorium::VERSION
    s.authors     = ["Stéphane D'Alu"]
    s.email       = ["sdalu@sdalu.com"]

    s.summary     = "Learn sensors' offsets from their history, fuse " \
                    "their readings"
    s.description = "Sensors of one quantity sharing a location rarely " \
                    "agree. Sensorium learns from their history how each " \
                    "reads against a reference (a constant, switched " \
                    "influences, a gain, a neighbour; modes learned " \
                    "apart, per regime), corrects each reading back to " \
                    "it, and fuses them by inverse variance into one " \
                    "value with its σ. Any quantity: a transform takes it " \
                    "where errors add up (relative humidity as absolute " \
                    "humidity). Standard library only; Sequel for the " \
                    "optional SQL store."
    s.homepage    = "https://github.com/sdalu/sensorium"
    s.license     = "MIT"

    s.required_ruby_version = ">= 3.4"

    s.metadata = {
        "homepage_uri" => s.homepage,
        "rubygems_mfa_required" => "true"
    }

    s.files = Dir.chdir(__dir__) do
        Dir["{lib}/**/*", "LICENSE.txt", "README.md"]
            .reject { |f| File.directory?(f) }
    end

    s.require_paths = ["lib"]
end
