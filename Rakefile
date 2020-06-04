# frozen_string_literal: true

require 'puppet_litmus/rake_tasks' if Bundler.rubygems.find_name('puppet_litmus').any?
require 'puppetlabs_spec_helper/rake_tasks'
require 'puppet-syntax/tasks/puppet-syntax'
require 'puppet_blacksmith/rake_tasks' if Bundler.rubygems.find_name('puppet-blacksmith').any?
require 'github_changelog_generator/task' if Bundler.rubygems.find_name('github_changelog_generator').any?
require 'puppet-strings/tasks' if Bundler.rubygems.find_name('puppet-strings').any?

def changelog_user
  return unless Rake.application.top_level_tasks.include? "changelog"
  returnVal = nil || JSON.load(File.read('metadata.json'))['author']
  raise "unable to find the changelog_user in .sync.yml, or the author in metadata.json" if returnVal.nil?
  puts "GitHubChangelogGenerator user:#{returnVal}"
  returnVal
end

def changelog_project
  return unless Rake.application.top_level_tasks.include? "changelog"

  returnVal = nil
  returnVal ||= begin
    metadata_source = JSON.load(File.read('metadata.json'))['source']
    metadata_source_match = metadata_source && metadata_source.match(%r{.*\/([^\/]*?)(?:\.git)?\Z})

    metadata_source_match && metadata_source_match[1]
  end

  raise "unable to find the changelog_project in .sync.yml or calculate it from the source in metadata.json" if returnVal.nil?

  puts "GitHubChangelogGenerator project:#{returnVal}"
  returnVal
end

def changelog_future_release
  return unless Rake.application.top_level_tasks.include? "changelog"
  returnVal = "v%s" % JSON.load(File.read('metadata.json'))['version']
  raise "unable to find the future_release (version) in metadata.json" if returnVal.nil?
  puts "GitHubChangelogGenerator future_release:#{returnVal}"
  returnVal
end

PuppetLint.configuration.send('disable_relative')

if Bundler.rubygems.find_name('github_changelog_generator').any?
  GitHubChangelogGenerator::RakeTask.new :changelog do |config|
    raise "Set CHANGELOG_GITHUB_TOKEN environment variable eg 'export CHANGELOG_GITHUB_TOKEN=valid_token_here'" if Rake.application.top_level_tasks.include? "changelog" and ENV['CHANGELOG_GITHUB_TOKEN'].nil?
    config.user = "#{changelog_user}"
    config.project = "#{changelog_project}"
    config.future_release = "#{changelog_future_release}"
    config.exclude_labels = ['maintenance']
    config.header = "# Change log\n\nAll notable changes to this project will be documented in this file. The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/) and this project adheres to [Semantic Versioning](http://semver.org)."
    config.add_pr_wo_labels = true
    config.issues = false
    config.merge_prefix = "### UNCATEGORIZED PRS; GO LABEL THEM"
    config.configure_sections = {
      "Changed" => {
        "prefix" => "### Changed",
        "labels" => ["backwards-incompatible"],
      },
      "Added" => {
        "prefix" => "### Added",
        "labels" => ["feature", "enhancement"],
      },
      "Fixed" => {
        "prefix" => "### Fixed",
        "labels" => ["bugfix"],
      },
    }
  end
else
  desc 'Generate a Changelog from GitHub'
  task :changelog do
    raise <<EOM
The changelog tasks depends on unreleased features of the github_changelog_generator gem.
Please manually add it to your .sync.yml for now, and run `pdk update`:
---
Gemfile:
  optional:
    ':development':
      - gem: 'github_changelog_generator'
        git: 'https://github.com/skywinder/github-changelog-generator'
        ref: '20ee04ba1234e9e83eb2ffb5056e23d641c7a018'
        condition: "Gem::Version.new(RUBY_VERSION.dup) >= Gem::Version.new('2.2.2')"
EOM
  end
end

# ACCEPTANCE TEST RAKE TASKS + HELPERS

namespace :acceptance do
  require 'puppet_litmus/rake_tasks'
  require_relative './spec/support/acceptance/litmus_helpers'

  def cmdb_record_ids
    inventory_hash = LitmusHelpers.inventory_hash_from_inventory_file
    vars = inventory_hash['vars'] || {}
    vars['cmdb_record_ids'] || {}
  end

  desc 'Provisions the VMs. This is currently just the master'
  task :provision_vms do
    if File.exist?('inventory.yaml')
      # Check if a master VM's already been setup
      begin
        uri = on_master(&:uri)
        puts("A master VM at '#{uri}' has already been set up")
        next
      rescue TargetNotFoundError
        # Pass-thru, this means that we haven't set up the master VM
      end
    end

    Rake::Task['litmus:provision_list'].invoke('acceptance')
  end

  desc 'Sets up PE on the master'
  task :setup_pe do
    on_master { |master| master.bolt_run_script('spec/support/acceptance/install_pe.sh') }
  end

  desc 'Sets up the ServiceNow instance'
  task :setup_servicenow_instance do
    begin
      # Check if the ServiceNow instance has been set up
      uri = on_servicenow_instance(&:uri)
      puts("A ServiceNow instance at '#{uri}' has already been set up")
      next
    rescue TargetNotFoundError
      # Pass-thru, this means that we haven't set up the ServiceNow instance
    end

    # Start the mock ServiceNow instance
    on_master do |master|
      puts("Starting the mock ServiceNow instance at the master (#{master.uri})")
      master.bolt_upload_file('./spec/support/acceptance/servicenow', '/tmp/servicenow')
      master.bolt_run_script('spec/support/acceptance/start_mock_servicenow_instance.sh')
    end

    # Update the inventory file
    puts('Updating the inventory.yaml file with the mock ServiceNow instance credentials')
    inventory_hash = LitmusHelpers.inventory_hash_from_inventory_file
    servicenow_group = inventory_hash['groups'].find { |g| g['name'] =~ %r{servicenow} }
    unless servicenow_group
      servicenow_group = { 'name' => 'servicenow_nodes' }
      inventory_hash['groups'].push(servicenow_group)
    end
    servicenow_group['targets'] = [{
      'uri' => "#{on_master(&:uri)}:1080",
      'config' => {
        'transport' => 'remote',
        'remote' => {
          'user' => 'mock_user',
          'password' => 'mock_password'
        }
      },
      'vars' => {
        'is_servicenow_instance' => true
      }
    }]
    write_to_inventory_file(inventory_hash, 'inventory.yaml')
  end

  desc 'Sets up the ServiceNow CMDB with entries for each VM'
  task :setup_servicenow_cmdb do
    if sys_id = cmdb_record_ids[on_master(&:uri)]
      # Double-check that the CMDB record exists on the ServiceNow instance
      task_result = on_servicenow_instance do |instance|
        instance.run_bolt_task(
          'servicenow_tasks::get_record',
          { 'table' => 'cmdb_ci', 'sys_id' => sys_id },
          expect_failures: true,
        )
      end
      if error = task_result.result['error']
        raise "inventory.yaml reports a sys_id of #{sys_id} for master's CMDB record, but servicenow_tasks::get_record fails to retrieve the record: #{error}"
      end
      puts("A CMDB record's already been created for the master (sys_id = #{sys_id})")
      next
    end

    # CMDB record doesn't exist so create it
    puts("Creating the master's CMDB record ...")
    cmdb_record = JSON.parse(File.read('spec/support/acceptance/cmdb_record_template.json'))
    cmdb_record['fqdn'] = on_master(&:uri)
    task_result = on_servicenow_instance do |instance|
      instance.run_bolt_task(
        'servicenow_tasks::create_record',
        { 'table' => 'cmdb_ci', 'fields' => cmdb_record } 
      )
    end
    sys_id = task_result.result['result']['sys_id']

    # Add the CMDB record to the inventory.yaml file
    master_uri = on_master(&:uri)
    inventory_hash = inventory_hash_from_inventory_file
    inventory_hash['vars'] = {
      'cmdb_record_ids' => cmdb_record_ids.merge(master_uri => sys_id),
    }
    puts("Adding the created CMDB record (sys_id = #{sys_id}) to inventory['vars'] ...")
    write_to_inventory_file(inventory_hash, 'inventory.yaml')
  end

  desc 'Installs the module on the master'
  task :install_module do
    on_master { |master| Rake::Task['litmus:install_module'].invoke(master.uri) }
  end

  desc 'Set up the test infrastructure'
  task :setup do
    tasks = [
      :provision_vms,
      :setup_pe,
      :setup_servicenow_instance,
      :setup_servicenow_cmdb,
      :install_module,
    ]

    tasks.each do |task|
      task = "acceptance:#{task}"
      puts("Invoking #{task}")
      Rake::Task[task].invoke
      puts("")
    end
  end

  desc 'Runs the tests'
  task :run_tests do
    puts("Running the tests ...\n")

    # TODO: We can't use litmus:acceptance:parallel here b/c that will try
    # to run the spec tests on _all_ targets in the inventory.yaml file,
    # including our ServiceNow instance. Until litmus:acceptance:parallel
    # has a way for you to pass-in specific targets to run the tests on,
    # we'll just run these tests via rspec
    system({ 'TARGET_HOST' => on_master(&:uri) }, 'bundle exec rspec ./spec/acceptance')
  end

  desc 'Teardown the setup'
  task :tear_down do
    puts("Tearing down the test infrastructure ...\n")

    inventory_hash = LitmusHelpers.inventory_hash_from_inventory_file

    # First, delete all created CMDB entries from the given ServiceNow
    # instance
    on_servicenow_instance do |instance|
      # Skip if the instance URI points to the mock ServiceNow instance
      # since that will be destroyed when we teardown the master via
      # Litmus
      next if instance.uri =~ Regexp.new(Regexp.escape(on_master(&:uri)))
      puts("Deleting test-specific CMDB records from #{instance.uri} ...")

      record_ids = cmdb_record_ids
      record_ids.each do |uri, sys_id|
        begin
          puts("Deleting #{uri}'s CMDB record (sys_id = #{sys_id}) ...")
          instance.run_bolt_task(
            'servicenow_tasks::delete_record',
            { 'table' => 'cmdb_ci', 'sys_id' => sys_id },
          )
          record_ids.delete(sys_id)
        rescue => e
          # Update the inventory.yaml file to remove deleted CMDB records
          inventory_hash['vars']['cmdb_record_ids'] = record_ids
          write_to_inventory_file(inventory_hash, 'inventory.yaml')
          raise e
        end
      end
    end

    # Now teardown the master
    Rake::Task['litmus:tear_down'].invoke(on_master(&:uri))

    # Delete the inventory file
    FileUtils.rm_f('inventory.yaml')
  end

  desc 'Task for CI'
  task :ci_run_tests do
    Rake::Task['acceptance:setup'].invoke
    Rake::Task['acceptance:run_tests'].invoke 
    Rake::Task['acceptance:tear_down'].invoke
  end
end
