require 'virtus'
require 'rom/support/deprecations'

module ROM
  module Rails
    class Configuration
      extend ROM::Deprecations

      include Virtus.model(strict: true)

      attribute :gateways, Hash, default: {}
      attribute :auto_registration_paths, Array, default: []

      deprecate :repositories, :gateways
    end
  end
end
