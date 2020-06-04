# rubocop:disable Style/AccessorMethodName

require './spec/support/acceptance/litmus_helpers.rb'

def set_sitepp_content(manifest)
  content = <<-HERE
  node default {
    #{manifest}
  }
  HERE

  on_master do |master|
    master.run_shell("echo '#{content}' > /etc/puppetlabs/code/environments/production/manifests/site.pp")
  end
end

def trigger_puppet_run(target, acceptable_exit_codes: [0, 2])
  result = target.run_shell('puppet agent -t --detailed-exitcodes', expect_failures: true)
  unless acceptable_exit_codes.include?(result[:exit_code])
    raise "Puppet run failed\nstdout: #{result[:stdout]}\nstderr: #{result[:stderr]}"
  end
  result
end

def capture_trusted_notice(report)
  # If you apply the Manifests::TRUSTED_EXTERNAL_VARIABLE manifest it will emit a notice
  # that will contain the contents of the $trusted variable. This function will capture
  json_regex = %r{defined 'message' as '(?<trusted_json>.+)'}

  matches = report[:stdout].match(json_regex)
  raise 'trusted external json content not found' if matches.nil?
  parsed_data = JSON.parse(matches[:trusted_json], symbolize_names: true)
  parsed_data.dig :external, :servicenow
end
