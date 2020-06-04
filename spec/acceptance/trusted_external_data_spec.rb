require 'spec_helper_acceptance'

context 'trusted external data' do
  # Set up the trusted external command on the master
  #
  # TODO: Should this move to suite-level or even Rakefile-level
  # setup? Because other tests like the classification test will
  # also depend on it so running this all the time can get annoying.
  before(:all) do
    # TODO: Should this move to setup?
    inventory_hash = inventory_hash_from_inventory_file
    servicenow_instance_uri = on_servicenow_instance(&:uri)
    servicenow_bolt_config = LitmusHelpers.config_from_node(inventory_hash, servicenow_instance_uri)
    servicenow_config = servicenow_bolt_config['remote']
    manifest = <<-MANIFEST
class { 'servicenow_cmdb_integration::trusted_external_command':
    instance => '#{servicenow_instance_uri}',
    user     => '#{servicenow_config['user']}',
    password => '#{servicenow_config['password']}',
}
    MANIFEST

    on_master do |master|
      master.idempotent_apply(manifest)
    end
  end

  context '$trusted.external.servicenow hash' do
    separator = '<trusted_json>'

    before(:all) do
      manifest = <<-MANIFEST
$trusted_json = inline_template("<%= @trusted.to_json %>")
notify { "trusted external data":
  message => "#{separator}${trusted_json}#{separator}"
}
      MANIFEST
      # TODO: This will cause some problems if we run the tests
      # in parallel. For example, what happens if two targets
      # try to modify site.pp at the same time?
      set_sitepp_content(manifest)
    end

    after(:all) do
      set_sitepp_content('')
    end

    it "contains the node's CMDB record" do
      result = trigger_puppet_run(LitmusHelpers.instance)
      puppet_output = result.stdout

      trusted_json = nil
      begin
        trusted_json = puppet_output.split(separator)[1]
        if trusted_json.nil?
          raise "Puppet output does not contain the expected '#{separator}<trusted_json>#{separator}' output"
        end
        trusted_json = JSON.parse(trusted_json)
      rescue => e
        raise "Failed to parse the trusted JSON: #{e}"
      end

      inventory_hash = LitmusHelpers.inventory_hash_from_inventory_file
      cmdb_record_id = inventory_hash['vars']['cmdb_record_ids'][LitmusHelpers.instance.uri]

      # The unit tests already check against the entire CMDB record JSON so it's
      # enough for the acceptance tests to check the sys_id when asserting that
      # the $trusted.external.servicenow hash contains the right CMDB record
      expect(trusted_json['external']['servicenow']['sys_id']).to eql(cmdb_record_id)
    end
  end
end
