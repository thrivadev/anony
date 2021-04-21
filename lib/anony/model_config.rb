# frozen_string_literal: true

require "active_support/core_ext/module/delegation"

require_relative "./strategies/destroy"
require_relative "./strategies/overwrite"

require_relative "./audit_logs/audited/config"

module Anony
  class ModelConfig
    # @api private
    class UndefinedStrategy
      def valid?
        false
      end

      def validate!
        raise ArgumentError, "Must specify either :destroy or :overwrite strategy"
      end
    end

    # @api private
    # Constructs a new instance of ModelConfig.
    #
    # @param [ActiveRecord::Base] model_class The model class the config is attached to.
    # @yield [block] For configuration of the ModelConfig instance.
    #
    # @example
    #   Anony::ModelConfig.new(Manager) { destroy }
    def initialize(model_class, &block)
      @model_class = model_class
      @strategy = UndefinedStrategy.new
      @audit_log_config = nil
      @skip_filter = nil
      instance_exec(&block) if block
    end

    # @api private
    # Applies the given strategy, taking into account any filters or conditions.
    #
    # @example
    #   Anony::ModelConfig.new(Manager).apply(Manager.new)
    def apply(instance)
      return Result.skipped if @skip_filter && instance.instance_exec(&@skip_filter)

      result = nil

      if @audit_log_config
        # Do not generate an audit log entry when anonymising the record.
        @audit_log_config.skip_auditing do
          result = @strategy.apply(instance)
        end

        result.audit_log_changes = @audit_log_config.apply(instance)
      else
        result = @strategy.apply(instance)
      end

      result
    end

    def valid?
      @strategy.valid? && (@audit_log_config ? @audit_log_config.valid? : true)
    end

    def validate!
      @strategy.validate!
      @audit_log_config&.validate!
    end

    # Use the deletion strategy instead of anonymising individual fields. This method is
    # incompatible with the fields strategy.
    #
    # This method takes no arguments or blocks.
    #
    # @example
    #   anonymise do
    #     destroy
    #   end
    def destroy
      raise ArgumentError, ":destroy takes no block" if block_given?
      unless @strategy.is_a?(UndefinedStrategy)
        raise ArgumentError, "Cannot specify :destroy when another strategy already defined"
      end

      @strategy = Strategies::Destroy.new
    end

    # Use the overwrite strategy to configure rules for individual fields. This method is
    # incompatible with the destroy strategy.
    #
    # This method takes a configuration block. All configuration is applied to
    # Anony::Strategies::Overwrite.
    #
    # @see Anony::Strategies::Overwrite
    #
    # @example
    #   anonymise do
    #     overwrite do
    #       hex :first_name
    #     end
    #   end
    def overwrite(&block)
      unless @strategy.is_a?(UndefinedStrategy)
        raise ArgumentError, "Cannot specify :overwrite when another strategy already defined"
      end

      @strategy = Strategies::Overwrite.new(@model_class, &block)
    end

    def audit_log(audit_log_extension, &block)
      # TODO: Make use of a registry where extension gems can register themselves
      # rather than this hard-coded case statement.
      case audit_log_extension
      when :audited
        @audit_log_config = AuditLogs::Audited::Config.new(@model_class, &block)
      else
        raise UnsupportedAuditLogException, audit_log_extension
      end
    end

    # Prevent any anonymisation strategy being applied when the provided block evaluates
    # to true. The block is executed in the model context.
    #
    # @example
    #   anonymise do
    #     skip_if { !persisted? }
    #   end
    def skip_if(&if_condition)
      raise ArgumentError, "Block required for :skip_if" unless if_condition

      @skip_filter = if_condition
    end
  end
end
