# frozen_string_literal: true

module Sensorium
    # An optional layer over the Fusion: a location's fused values
    # followed over time by a scalar Kalman filter, in the transform's
    # space. Between two Fused it predicts with the location's
    # Dynamics::Model for the moment's regime (Parts::Driven: the
    # outside within max_age, the Switches on, none while a Mode holds),
    # its variance growing by q × hours; without one, the value stays and
    # its variance grows by (drift × hours)². Each Fused with a value and
    # a σ then updates it. The Fusion stays a function of its snapshot:
    # the State is the caller's, given back at each step, kept by a store
    # if it must outlive the process.
    class Filter
        # value and variance in the transform's space; at, the moment
        # of the last Fused taken in.
        State = Data.define(:location, :quantity, :at, :value, :variance)

        # dynamics: [Dynamics::Model]; locations: { name => Location },
        # those set; all of the setup's quantity.
        def initialize(setup, dynamics: [], locations: {})
            @setup     = setup
            @dynamics  = dynamics.to_h { [[it.location, it.regime], it] }
            @locations = locations
        end

        # The State after a Fused: predicted to its moment, then updated
        # by it when it has a value and a σ. A first Fused starts the
        # State (nil without a value and a σ); one older than the State
        # leaves it as it is. snapshot: the one the Fused was made from,
        # for the model's inputs (without it, the drift rule).
        def step(state, fused, snapshot: nil)
            return start(fused) unless state
            check(state, fused)
            return state if fused.at < state.at
            update(predict(state, fused.at, snapshot), fused)
        end

        # The State moved to `at`, with the inputs of the snapshot; `at`
        # earlier than the state's moment leaves it unchanged.
        def predict(state, at, snapshot = nil)
            return state if at < state.at
            hours = (at - state.at) / 3600.0
            change, spread = modelled(state, hours, snapshot) ||
                             [0.0, (settings(state.location).drift * hours)**2]
            state.with(at:, value: state.value + change,
                       variance: state.variance + spread)
        end

        # The State as the quantity reads: an Estimate brought back with
        # the context (a humidity at the location's temperature).
        def estimate(state, context = {})
            transform = @setup.quantity.transform
            value = transform.inverse(state.value, context)
            sigma = value && transform.sigma(Math.sqrt(state.variance),
                                             state.value, value)
            Estimate.new(value:, sigma:)
        end

        private

        def start(fused)
            inside = fused.inside
            return unless inside.value && inside.sigma
            State.new(location: fused.location, quantity: fused.quantity,
                      at: fused.at, value: inside.value,
                      variance: inside.sigma**2)
        end

        def check(state, fused)
            same!(state.location, fused.location, "location")
            same!(state.quantity, fused.quantity, "quantity")
            same!(state.quantity, @setup.quantity.name, "quantity")
        end

        def same!(have, want, label)
            return if have == want
            raise ArgumentError, "a #{label} of #{want} for #{have}"
        end

        # The Kalman update by the Fused, when it has a value and a σ.
        def update(state, fused)
            seen = fused.inside
            return state unless seen.value && seen.sigma
            corrected(state, seen, gain(state.variance, seen.sigma**2))
        end

        def corrected(state, seen, gain)
            state.with(value: state.value + (gain * (seen.value - state.value)),
                       variance: state.variance * (1 - gain))
        end

        def gain(prior, noise) = prior / (prior + noise)

        # [change, variance] by the model; nil without one or its inputs.
        def modelled(state, hours, snapshot)
            return unless snapshot
            key = [state.location, @setup.regime.of(snapshot.at)]
            Parts::Driven.new(settings(state.location), @dynamics[key],
                              snapshot, @setup).of(state.value, hours)
        end

        def settings(name)
            @locations.fetch(name) { Location.default(name) }
                      .resolve(@setup.quantity)
        end
    end
end
