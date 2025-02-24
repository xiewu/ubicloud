# frozen_string_literal: true

UbiRodish.on("vm").run_on("sftp") do
  skip_option_parsing

  args(0...)

  run do |argv, opts|
    handle_ssh(opts) do |user:, address:|
      address = "[#{address}]" if address.include?(":")
      ["sftp", *argv, "--", "#{user}@#{address}"]
    end
  end
end
