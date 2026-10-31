# frozen_string_literal: true

module Sensorium
    module Store
        class Sequel
            # A sensor gone for good, dropped on demand.
            module Forget
                def forget(quantity, location, device)
                    key = { quantity:, location:, device: }
                    @db.transaction do
                        %i[offsets shifts tracks].each do |name|
                            table(name).where(key).delete
                        end
                    end
                end
            end
        end
    end
end
