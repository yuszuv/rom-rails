require 'rails'

require 'rom/rails/inflections'
require 'rom/rails/configuration'
require 'rom/rails/controller_extension'
require 'rom/rails/active_record/configuration'

Spring.after_fork { ROM::Rails::Railtie.disconnect } if defined?(Spring)

module ROM
  module Rails
    class Railtie < ::Rails::Railtie
      COMPONENT_DIRS = %w(relations mappers commands).freeze

      MissingGatewayConfigError = Class.new(StandardError)

      # Make `ROM::Rails::Configuration` instance available to the user via
      # `Rails.application.config` before other initializers run.
      config.before_configuration do |_app|
        config.rom = Configuration.new
      end

      initializer 'rom.configure_action_controller' do
        ActiveSupport.on_load(:action_controller) do
          ActionController::Base.send(:include, ControllerExtension)
          ActionController::API.send(:include, ControllerExtension) if defined?(ActionController::API)
        end
      end

      initializer 'rom.adjust_eager_load_paths' do |app|
        paths =
          auto_registration_paths.inject([]) do |result, root_path|
            result.concat(COMPONENT_DIRS.map { |dir| ::Rails.root.join(root_path, dir).to_s })
          end

        app.config.eager_load_paths -= paths
      end

      rake_tasks do
        load "rom/rails/tasks/db.rake" unless active_record?
      end

      # Reload ROM-related application code on each request.
      config.to_prepare do |_config|
        ROM.env = Railtie.create_container
      end

      console do |_app|
        Railtie.configure_console_logger
      end

      # Behaves like `Railtie#configure` if the given block does not take any
      # arguments. Otherwise yields the ROM configuration to the block.
      #
      # @example
      #   ROM::Rails::Railtie.configure do |config|
      #     config.gateways[:default] = [:yaml, 'yaml:///data']
      #     config.auto_registration_paths += [MyEngine.root]
      #   end
      #
      # @api public
      def configure(&block)
        config.rom = Configuration.new unless config.respond_to?(:rom)

        if block.arity == 1
          block.call(config.rom)
        else
          super
        end
      end

      def create_configuration
        ROM::Configuration.new(gateways)
      end

      # @api private
      def create_container
        configuration = create_configuration

        auto_registration_paths.each do |root_path|
          configuration.auto_registration(::Rails.root.join(root_path), namespace: true)
        end

        ROM.container(configuration)
      end

      # @api private
      def gateways
        if active_record?
          load_active_record_config.each do |name, spec|
            config.rom.gateways[name] ||= [:sql, spec[:uri], spec[:options]]
          end
        end

        if config.rom.gateways.empty?
          ::Rails.logger.warn "It seems that you have not configured any gateways"

          config.rom.gateways[:default] = [ :memory, "memory://test" ]
        end

        config.rom.gateways
      end

      # Attempt to infer all configured gateways from activerecord
      def load_active_record_config
        ROM::Rails::ActiveRecord::Configuration.new.call
      end

      def load_initializer
        load "#{root}/config/initializers/rom.rb"
      rescue LoadError
        # do nothing
      end

      # @api private
      def disconnect
        container.disconnect unless container.nil?
      end

      # @api private
      def root
        ::Rails.root
      end

      def container
        ROM.env
      end

      def auto_registration_paths
        config.rom.auto_registration_paths + [root]
      end

      # @api private
      def active_record?
        defined?(::ActiveRecord)
      end

      # @api private
      def std_err_out_logger?
        ActiveSupport::Logger.logger_outputs_to?(::Rails.logger, STDERR, STDOUT)
      end

      # @api private
      def configure_console_logger
        return if active_record? || std_err_out_logger?

        console = ActiveSupport::Logger.new(STDERR)
        ::Rails.logger.extend ActiveSupport::Logger.broadcast console
      end
    end
  end
end
