# frozen_string_literal: true

module Sensorium
    module Dynamics
        # A regime's steps fitted by least squares: the change on the gap
        # to the outside (when there is one), on each Switch that was
        # both on and off over the steps (one never off or never on
        # cannot be told from c), and on 1.
        module Regression
            module_function

            # The Model, nil when the steps are fewer than
            # setup.min_samples, the fit is singular, or a is negative.
            def model(key, steps, setup)
                return if steps.size < setup.min_samples
                names = varying(steps)
                rows = steps.map { row(it, names) }
                found = solve(rows, steps.map(&:change)) or return
                terms = terms(found, names, steps.first.gap)
                return if terms[:a].negative?
                Model.new(**key, **terms, **noise(rows, steps, found, setup))
            end

            # q, and what it was measured over.
            def noise(rows, steps, found, setup)
                { q: per_hour(rows, steps, found, setup.bin), bin: setup.bin,
                  steps: steps.size }
            end

            # The Switches both on and off over the steps.
            def varying(steps)
                seen = steps.map { it.on.to_set }
                seen.reduce(:|).select do |name|
                    seen.any? { !it.include?(name) }
                end.sort
            end

            def row(step, names)
                [*([step.gap] if step.gap),
                 *names.map { step.on.include?(it) ? 1.0 : 0.0 }, 1.0]
            end

            # a, b and c from β; a is 0 without an outside.
            def terms(found, names, gap)
                a = gap ? found.first : 0.0
                b = found.drop(gap ? 1 : 0).first(names.size)
                { a:, b: names.zip(b).to_h, c: found.last }
            end

            # The variance of what the fit leaves, per step (over n - p),
            # brought to an hour.
            def per_hour(rows, steps, found, bin)
                left = rows.zip(steps).sum do |row, step|
                    (step.change - Stats.dot(row, found))**2
                end
                left / (rows.size - found.size) * 3600 / bin
            end

            # β of y on the rows, by the normal equations of the columns
            # each brought to a unit norm (a gap of tens of degrees and
            # a 0/1 Switch alike); nil when singular.
            def solve(rows, ys)
                norms = rows.transpose.map { Math.sqrt(Stats.dot(it, it)) }
                return if norms.any?(&:zero?)
                scaled = rows.map { it.zip(norms).map { |x, n| x / n } }
                found = Gauss.solve(normal(scaled, ys)) or return
                found.zip(norms).map { |x, n| x / n }
            end

            # [XᵀX | Xᵀy].
            def normal(rows, ys)
                columns = rows.transpose
                columns.map do |x|
                    columns.map { Stats.dot(x, it) } << Stats.dot(x, ys)
                end
            end
        end

        # Gaussian elimination with partial pivoting of an augmented
        # matrix [A | y], A of a unit diagonal's scale.
        module Gauss
            module_function

            TINY = 1e-12

            # x of A x = y; nil when A is singular.
            def solve(matrix)
                singular = (0...matrix.size).any? do |k|
                    pivot(matrix, k)
                    next true if matrix[k][k].abs <= TINY
                    eliminate(matrix, k)
                    false
                end
                back(matrix) unless singular
            end

            def pivot(matrix, k)
                best = (k...matrix.size).max_by { matrix[it][k].abs }
                matrix[k], matrix[best] = matrix[best], matrix[k]
            end

            def eliminate(matrix, k)
                ((k + 1)...matrix.size).each do |i|
                    factor = matrix[i][k] / matrix[k][k]
                    matrix[i] = matrix[i].zip(matrix[k]).map do |x, y|
                        x - (factor * y)
                    end
                end
            end

            def back(matrix)
                size = matrix.size
                (size - 1).downto(0).each_with_object([]) do |i, x|
                    row = matrix[i]
                    known = ((i + 1)...size).sum { row[it] * x[it] }
                    x[i] = (row[size] - known) / row[i]
                end
            end
        end
    end
end
