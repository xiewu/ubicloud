# frozen_string_literal: true

UbiCli.on("lb").run_on("attach-vm") do
  desc "Attach a virtual machine to a load balancer"

  banner "ubi lb (location/lb-name | lb-id) attach-vm vm-id"

  args 1

  run do |vm_id|
    post(lb_path("/attach-vm"), "vm_id" => vm_id) do |data|
      ["Attached VM with id #{vm_id} to load balancer with id #{data["id"]}"]
    end
  end
end
