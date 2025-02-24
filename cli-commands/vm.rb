# frozen_string_literal: true

UbiCli.base("vm") do
  post_options("ubi vm location-name/(vm-name|_vm-ubid) [options] subcommand [...]", key: :vm_ssh) do
    on("-4", "--ip4", "use IPv4 address")
    on("-6", "--ip6", "use IPv6 address")
    on("-u", "--user user", "override username")
  end
end
