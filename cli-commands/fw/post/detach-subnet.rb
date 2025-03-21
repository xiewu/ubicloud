# frozen_string_literal: true

UbiCli.on("fw").run_on("detach-subnet") do
  desc "Detch a private subnet from a firewall"

  banner "ubi fw (location/fw-name | fw-id) detach-subnet ps-id"

  args 1

  run do |subnet_id|
    post(fw_path("/detach-subnet"), "private_subnet_id" => subnet_id) do |data|
      ["Detached private subnet with id #{subnet_id} from firewall with id #{data["id"]}"]
    end
  end
end
