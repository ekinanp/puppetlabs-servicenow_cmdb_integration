require 'puppet_litmus'

class LitmusTarget
  include PuppetLitmus

  attr_reader :uri

  def initialize(uri)
    @uri = uri
  end
end

module LitmusHelpers
  extend PuppetLitmus

  def self.instance
    target_host = ENV['TARGET_HOST']
    unless target_host
      raise "LitmusHelpers.instance can only be called when running the tests (when ENV['TARGET_HOST'] is set)"
    end
    LitmusTarget.new(ENV['TARGET_HOST'])
  end
end

# These helpers are a useful way for tests to reuse
# Litmus' helpers when they want to do stuff on nodes
# that may not be the current target host (like e.g.
# the master or the ServiceNow instance).
#
# NOTE: This is definitely hacky and should be revisited
# once puppet-litmus is more polished or we have a better
# understanding of its design.

def on_master
  on_target('master', 'acceptance:provision_vms', 'is_master') do |master|
    yield master
  end
end

def on_servicenow_instance
  on_target('ServiceNow instance', 'acceptance:setup_servicenow_instance', 'is_servicenow_instance') do |servicenow_instance|
    yield servicenow_instance
  end
end

class TargetNotFoundError < StandardError
end

def on_target(name, setup_task, classifying_var)
  @targets ||= {}

  unless @targets[name]
    # Find the target
    inventory_hash = LitmusHelpers.inventory_hash_from_inventory_file
    targets = LitmusHelpers.find_targets(inventory_hash, nil)
    target_uri = targets.find do |target|
      vars = LitmusHelpers.vars_from_node(inventory_hash, target)
      vars ? vars[classifying_var] : nil
    end
    unless target_uri
      raise TargetNotFoundError, "none of the targets in 'inventory.yaml' have the '#{classifying_var}' var set. Did you forget to run 'rake #{setup_task}'?"
    end
    @targets[name] = LitmusTarget.new(target_uri)
  end

  old_target_host = ENV['TARGET_HOST']
  target_obj = @targets[name]
  begin
    ENV['TARGET_HOST'] = target_obj.uri
    yield target_obj
  ensure
    ENV['TARGET_HOST'] = old_target_host
  end
end
