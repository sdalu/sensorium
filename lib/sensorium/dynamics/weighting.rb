# frozen_string_literal: true

module Sensorium
    module Dynamics
        # A Prior's weight in the least squares: for a coefficient β of
        # mean μ and σ, s² / σ² added to its diagonal and s² μ / σ² to
        # its right-hand side, s² the noise of a step, all in the
        # columns' unit-norm scale (β' = β × norm).
        module Weighting
            module_function

            # The matrix with the priors added, as is without any.
            def of(matrix, scaled, ys, priors, norms)
                return matrix unless priors&.any?
                add(matrix, priors, norms, noise(scaled, ys, matrix))
                matrix
            end

            # The noise of a step: the residual variance of the fit
            # without priors, or the changes' own when it is singular.
            def noise(scaled, ys, matrix)
                found = Gauss.solve(matrix.map(&:dup))
                return variance(ys) unless found
                left = scaled.zip(ys).map do |row, y|
                    y - Stats.dot(row, found)
                end
                Stats.dot(left, left) / [ys.size - found.size, 1].max
            end

            def variance(ys)
                mean = ys.sum / ys.size
                ys.sum { (it - mean)**2 } / [ys.size - 1, 1].max
            end

            # The matrix [XᵀX | Xᵀy] given each column's prior.
            def add(matrix, priors, norms, noise)
                priors.each_with_index do |prior, j|
                    next unless prior
                    mean, sigma = prior
                    weight = noise / ((sigma * norms[j])**2)
                    matrix[j][j] += weight
                    matrix[j][-1] += weight * mean * norms[j]
                end
            end
        end
    end
end
