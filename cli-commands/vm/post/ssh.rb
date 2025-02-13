# frozen_string_literal: true

UbiRodish.on("vm").run_on("ssh") do
  skip_option_parsing("ubi vm location-name/(vm-name|_vm-ubid) [options] ssh [ssh-options --] [ssh-args]")

  args(0...)

  run do |argv, opts|
    handle_ssh(opts) do |user:, address:|
      if (i = argv.index("--"))
        options = argv[0...i]
        argv = argv[(i + 1)...]
      end

      ["ssh", *options, "--", "#{user}@#{address}", *argv]
    end
  end
end
