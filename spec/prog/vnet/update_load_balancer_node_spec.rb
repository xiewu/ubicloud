# frozen_string_literal: true

RSpec.describe Prog::Vnet::UpdateLoadBalancerNode do
  subject(:nx) {
    described_class.new(st)
  }

  let(:st) {
    Strand.create_with_id(prog: "Vnet::UpdateLoadBalancerNode", stack: [{"subject_id" => vm.id, "load_balancer_id" => lb.id}], label: "update_load_balancer")
  }
  let(:lb) {
    prj = Project.create_with_id(name: "test-prj").tap { _1.associate_with_project(_1) }
    ps = Prog::Vnet::SubnetNexus.assemble(prj.id, name: "test-ps").subject
    Prog::Vnet::LoadBalancerNexus.assemble(ps.id, name: "test-lb", src_port: 80, dst_port: 8080).subject
  }
  let(:vm) {
    Prog::Vm::Nexus.assemble("pub-key", lb.projects.first.id, name: "test-vm", private_subnet_id: lb.private_subnet.id).subject
  }
  let(:neighbor_vm) {
    Prog::Vm::Nexus.assemble("pub-key", lb.projects.first.id, name: "neighbor-vm", private_subnet_id: lb.private_subnet.id).subject
  }

  before do
    lb.add_vm(vm)
    allow(nx).to receive_messages(vm: vm, load_balancer: lb)
    allow(vm).to receive_messages(ephemeral_net4: NetAddr::IPv4Net.parse("100.100.100.100/32"), ephemeral_net6: NetAddr::IPv6Net.parse("2a02:a464:deb2:a000::/64"))
    allow(vm).to receive(:vm_host).and_return(instance_double(VmHost, sshable: instance_double(Sshable)))
  end

  describe ".before_run" do
    it "simply pops if VM is destroyed" do
      expect(nx).to receive(:vm).and_return(nil)

      expect { nx.before_run }.to exit({"msg" => "VM is destroyed"})
    end

    it "doesn't do anything if the VM is not destroyed" do
      expect(nx).to receive(:vm).and_return(vm)

      expect { nx.before_run }.not_to exit
    end
  end

  describe ".cert_folder" do
    it "returns the certificate folder" do
      expect(nx.cert_folder).to eq("/vm/#{vm.inhost_name}/cert")
    end
  end

  describe ".cert_path" do
    it "returns the certificate path" do
      expect(nx.cert_path).to eq("/vm/#{vm.inhost_name}/cert/cert.pem")
    end
  end

  describe ".key_path" do
    it "returns the key path" do
      expect(nx.key_path).to eq("/vm/#{vm.inhost_name}/cert/key.pem")
    end
  end

  describe "#update_load_balancer" do
    context "when no healthy vm exists" do
      it "hops to remove load balancer" do
        expect(lb).to receive(:active_vms).and_return([])
        expect { nx.update_load_balancer }.to hop("remove_load_balancer")
      end

      it "removes the VM from load balancer and hops to remove_cert_server if the VM is detaching" do
        lb.load_balancers_vms_dataset.update(state: "detaching")
        expect(lb).to receive(:remove_vm).with(vm)
        expect { nx.update_load_balancer }.to hop("remove_cert_server")
      end
    end

    context "when a single vm exists and it is the subject" do
      let(:vmh) {
        instance_double(VmHost, sshable: instance_double(Sshable))
      }

      before do
        lb.load_balancers_vms_dataset.update(state: "up")
        allow(vm).to receive(:vm_host).and_return(vmh)
      end

      it "does not hop to remove load balancer and creates basic load balancing with nat" do
        expect(lb).to receive(:active_vms).and_return([vm]).at_least(:once)
        expect(vm.nics.first).to receive(:private_ipv4).and_return(NetAddr::IPv4Net.parse("192.168.1.0/32")).at_least(:once)
        expect(vm.nics.first).to receive(:private_ipv6).and_return(NetAddr::IPv6Net.parse("fd10:9b0b:6b4b:8fbb::/64")).at_least(:once)
        expect(vmh.sshable).to receive(:cmd).with("sudo ip netns exec #{vm.inhost_name} nft --file -", stdin: <<LOAD_BALANCER)
table ip nat;
delete table ip nat;
table inet nat;
delete table inet nat;
table inet nat {
  set neighbor_ips_v4 {
    type ipv4_addr;

  }

  set neighbor_ips_v6 {
    type ipv6_addr;

  }

  chain prerouting {
    type nat hook prerouting priority dstnat; policy accept;
    ip daddr 100.100.100.100/32 tcp dport 80 ct state established,related,new counter dnat to numgen inc mod 1 map { 0 : 192.168.1.0 . 8080 }
    ip6 daddr 2a02:a464:deb2:a000::2 tcp dport 80 ct state established,related,new counter dnat to numgen inc mod 1 map { 0 : fd10:9b0b:6b4b:8fbb::2 . 8080 }
    ip daddr 100.100.100.100/32 dnat to 192.168.1.0
  }

  chain postrouting {
    type nat hook postrouting priority srcnat; policy accept;
    ip daddr @neighbor_ips_v4 tcp dport 8080 ct state established,related,new counter snat to 192.168.1.0
    ip6 daddr @neighbor_ips_v6 tcp dport 8080 ct state established,related,new counter snat to fd10:9b0b:6b4b:8fbb::2
    ip saddr 192.168.1.0 ip daddr != { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } snat to 100.100.100.100/32
    ip saddr 192.168.1.0 ip daddr 192.168.1.0 snat to 100.100.100.100/32
  }
}
LOAD_BALANCER
        expect { nx.update_load_balancer }.to exit({"msg" => "load balancer is updated"})
      end

      it "creates basic load balancing with hashing" do
        lb.update(algorithm: "hash_based")
        expect(lb).to receive(:active_vms).and_return([vm]).at_least(:once)
        expect(vm.nics.first).to receive(:private_ipv4).and_return(NetAddr::IPv4Net.parse("192.168.1.0/32")).at_least(:once)
        expect(vm.nics.first).to receive(:private_ipv6).and_return(NetAddr::IPv6Net.parse("fd10:9b0b:6b4b:8fbb::/64")).at_least(:once)
        expect(vmh.sshable).to receive(:cmd).with("sudo ip netns exec #{vm.inhost_name} nft --file -", stdin: <<LOAD_BALANCER)
table ip nat;
delete table ip nat;
table inet nat;
delete table inet nat;
table inet nat {
  set neighbor_ips_v4 {
    type ipv4_addr;

  }

  set neighbor_ips_v6 {
    type ipv6_addr;

  }

  chain prerouting {
    type nat hook prerouting priority dstnat; policy accept;
    ip daddr 100.100.100.100/32 tcp dport 80 ct state established,related,new counter dnat to jhash ip saddr . tcp sport . ip daddr . tcp dport mod 1 map { 0 : 192.168.1.0 . 8080 }
    ip6 daddr 2a02:a464:deb2:a000::2 tcp dport 80 ct state established,related,new counter dnat to jhash ip6 saddr . tcp sport . ip6 daddr . tcp dport mod 1 map { 0 : fd10:9b0b:6b4b:8fbb::2 . 8080 }
    ip daddr 100.100.100.100/32 dnat to 192.168.1.0
  }

  chain postrouting {
    type nat hook postrouting priority srcnat; policy accept;
    ip daddr @neighbor_ips_v4 tcp dport 8080 ct state established,related,new counter snat to 192.168.1.0
    ip6 daddr @neighbor_ips_v6 tcp dport 8080 ct state established,related,new counter snat to fd10:9b0b:6b4b:8fbb::2
    ip saddr 192.168.1.0 ip daddr != { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } snat to 100.100.100.100/32
    ip saddr 192.168.1.0 ip daddr 192.168.1.0 snat to 100.100.100.100/32
  }
}
LOAD_BALANCER
        expect { nx.update_load_balancer }.to exit({"msg" => "load balancer is updated"})
      end
    end

    context "when multiple vms exist" do
      let(:vmh) {
        instance_double(VmHost, sshable: instance_double(Sshable))
      }

      before do
        allow(lb).to receive(:active_vms).and_return([vm, neighbor_vm]).at_least(:once)
        allow(vm).to receive(:vm_host).and_return(vmh)
        allow(vm.nics.first).to receive_messages(private_ipv4: NetAddr::IPv4Net.parse("192.168.1.0/32"), private_ipv6: NetAddr::IPv6Net.parse("fd10:9b0b:6b4b:8fbb::/64"))
        allow(neighbor_vm.nics.first).to receive_messages(private_ipv4: NetAddr::IPv4Net.parse("172.10.1.0/32"), private_ipv6: NetAddr::IPv6Net.parse("fd10:9b0b:6b4b:aaa::2/64"))
      end

      it "creates load balancing with multiple vms if all active" do
        expect(vm.vm_host.sshable).to receive(:cmd).with("sudo ip netns exec #{vm.inhost_name} nft --file -", stdin: <<LOAD_BALANCER)
table ip nat;
delete table ip nat;
table inet nat;
delete table inet nat;
table inet nat {
  set neighbor_ips_v4 {
    type ipv4_addr;
elements = {172.10.1.0}
  }

  set neighbor_ips_v6 {
    type ipv6_addr;
elements = {fd10:9b0b:6b4b:aaa::2}
  }

  chain prerouting {
    type nat hook prerouting priority dstnat; policy accept;
    ip daddr 100.100.100.100/32 tcp dport 80 ct state established,related,new counter dnat to numgen inc mod 2 map { 0 : 192.168.1.0 . 8080, 1 : 172.10.1.0 . 8080 }
    ip6 daddr 2a02:a464:deb2:a000::2 tcp dport 80 ct state established,related,new counter dnat to numgen inc mod 2 map { 0 : fd10:9b0b:6b4b:8fbb::2 . 8080, 1 : fd10:9b0b:6b4b:aaa::2 . 8080 }
    ip daddr 100.100.100.100/32 dnat to 192.168.1.0
  }

  chain postrouting {
    type nat hook postrouting priority srcnat; policy accept;
    ip daddr @neighbor_ips_v4 tcp dport 8080 ct state established,related,new counter snat to 192.168.1.0
    ip6 daddr @neighbor_ips_v6 tcp dport 8080 ct state established,related,new counter snat to fd10:9b0b:6b4b:8fbb::2
    ip saddr 192.168.1.0 ip daddr != { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } snat to 100.100.100.100/32
    ip saddr 192.168.1.0 ip daddr 192.168.1.0 snat to 100.100.100.100/32
  }
}
LOAD_BALANCER

        expect { nx.update_load_balancer }.to exit({"msg" => "load balancer is updated"})
      end

      it "creates load balancing with multiple vms if the vm we work on is down" do
        expect(lb).to receive(:active_vms).and_return([neighbor_vm]).at_least(:once)
        expect(vm.vm_host.sshable).to receive(:cmd).with("sudo ip netns exec #{vm.inhost_name} nft --file -", stdin: <<LOAD_BALANCER)
table ip nat;
delete table ip nat;
table inet nat;
delete table inet nat;
table inet nat {
  set neighbor_ips_v4 {
    type ipv4_addr;
elements = {172.10.1.0}
  }

  set neighbor_ips_v6 {
    type ipv6_addr;
elements = {fd10:9b0b:6b4b:aaa::2}
  }

  chain prerouting {
    type nat hook prerouting priority dstnat; policy accept;
    ip daddr 100.100.100.100/32 tcp dport 80 ct state established,related,new counter dnat to numgen inc mod 1 map { 0 : 172.10.1.0 . 8080 }
    ip6 daddr 2a02:a464:deb2:a000::2 tcp dport 80 ct state established,related,new counter dnat to numgen inc mod 1 map { 0 : fd10:9b0b:6b4b:aaa::2 . 8080 }
    ip daddr 100.100.100.100/32 dnat to 192.168.1.0
  }

  chain postrouting {
    type nat hook postrouting priority srcnat; policy accept;
    ip daddr @neighbor_ips_v4 tcp dport 8080 ct state established,related,new counter snat to 192.168.1.0
    ip6 daddr @neighbor_ips_v6 tcp dport 8080 ct state established,related,new counter snat to fd10:9b0b:6b4b:8fbb::2
    ip saddr 192.168.1.0 ip daddr != { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } snat to 100.100.100.100/32
    ip saddr 192.168.1.0 ip daddr 192.168.1.0 snat to 100.100.100.100/32
  }
}
LOAD_BALANCER

        expect { nx.update_load_balancer }.to exit({"msg" => "load balancer is updated"})
      end

      it "creates load balancing with multiple vms if the vm we work on is up but the neighbor is down" do
        expect(lb).to receive(:active_vms).and_return([vm]).at_least(:once)
        expect(vm.vm_host.sshable).to receive(:cmd).with("sudo ip netns exec #{vm.inhost_name} nft --file -", stdin: <<LOAD_BALANCER)
table ip nat;
delete table ip nat;
table inet nat;
delete table inet nat;
table inet nat {
  set neighbor_ips_v4 {
    type ipv4_addr;

  }

  set neighbor_ips_v6 {
    type ipv6_addr;

  }

  chain prerouting {
    type nat hook prerouting priority dstnat; policy accept;
    ip daddr 100.100.100.100/32 tcp dport 80 ct state established,related,new counter dnat to numgen inc mod 1 map { 0 : 192.168.1.0 . 8080 }
    ip6 daddr 2a02:a464:deb2:a000::2 tcp dport 80 ct state established,related,new counter dnat to numgen inc mod 1 map { 0 : fd10:9b0b:6b4b:8fbb::2 . 8080 }
    ip daddr 100.100.100.100/32 dnat to 192.168.1.0
  }

  chain postrouting {
    type nat hook postrouting priority srcnat; policy accept;
    ip daddr @neighbor_ips_v4 tcp dport 8080 ct state established,related,new counter snat to 192.168.1.0
    ip6 daddr @neighbor_ips_v6 tcp dport 8080 ct state established,related,new counter snat to fd10:9b0b:6b4b:8fbb::2
    ip saddr 192.168.1.0 ip daddr != { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } snat to 100.100.100.100/32
    ip saddr 192.168.1.0 ip daddr 192.168.1.0 snat to 100.100.100.100/32
  }
}
LOAD_BALANCER

        expect { nx.update_load_balancer }.to exit({"msg" => "load balancer is updated"})
      end

      it "raises exception if the algorithm is not supported" do
        expect(lb).to receive(:algorithm).and_return("least_conn").at_least(:once)
        expect { nx.update_load_balancer }.to raise_error("Unsupported load balancer algorithm: least_conn")
      end
    end
  end

  describe "#put_certificate" do
    let(:cert) {
      instance_double(Cert, cert: "cert", csr_key: OpenSSL::PKey::RSA.new(4096))
    }

    before do
      allow(lb).to receive(:active_cert).and_return(cert)
    end

    it "creates a certificate folder, puts the certificate and hops to start_certificate_server" do
      expect(vm.vm_host.sshable).to receive(:cmd).with("sudo -u #{vm.inhost_name} mkdir -p /vm/#{vm.inhost_name}/cert")
      expect(vm.vm_host.sshable).to receive(:cmd).with("sudo -u #{vm.inhost_name} tee /vm/#{vm.inhost_name}/cert/cert.pem", stdin: "cert")
      expect(vm.vm_host.sshable).to receive(:cmd).with("sudo -u #{vm.inhost_name} tee /vm/#{vm.inhost_name}/cert/key.pem", stdin: cert.csr_key.to_pem)
      expect { nx.put_certificate }.to hop("start_certificate_server")
    end
  end

  describe "#start_certificate_server" do
    it "starts the certificate server and pops" do
      service = <<SERVICE
[Unit]
Description=Certificate Server
After=network.target

[Service]
NetworkNamespacePath=/var/run/netns/#{vm.inhost_name}
ExecStart=busybox httpd -f -p [FD00:0B1C:100D:CE::]:8080 -h /vm/#{vm.inhost_name}/cert
Restart=always
Type=simple
ProtectSystem=strict
PrivateDevices=yes
PrivateTmp=yes
ProtectHome=yes
ProtectKernelModules=yes
ProtectKernelTunables=yes
ProtectControlGroups=yes
NoNewPrivileges=yes
ReadOnlyPaths=/vm/#{vm.inhost_name}/cert/cert.pem /vm/#{vm.inhost_name}/cert/key.pem
User=#{vm.inhost_name}
Group=#{vm.inhost_name}
SERVICE

      expect(vm.vm_host.sshable).to receive(:cmd).with("sudo -u #{vm.inhost_name} tee /vm/#{vm.inhost_name}/#{vm.inhost_name}_cert_server.service", stdin: service)

      expect(vm.vm_host.sshable).to receive(:cmd).with(<<CMD)
systemctl enable /vm/#{vm.inhost_name}/#{vm.inhost_name}_cert_server.service
systemctl daemon-reload
systemctl start #{vm.inhost_name}_cert_server
CMD

      expect { nx.start_certificate_server }.to exit({"msg" => "certificate server is started"})
    end
  end

  describe "#remove_cert_server" do
    it "removes the certificate files, server and hops to remove_load_balancer" do
      cmd = <<CMD
systemctl stop #{vm.inhost_name}_cert_server
systemctl disable #{vm.inhost_name}_cert_server
rm -f /vm/#{vm.inhost_name}/#{vm.inhost_name}_cert_server.service
rm -rf /vm/#{vm.inhost_name}/cert
systemctl daemon-reload
CMD

      expect(vm.vm_host.sshable).to receive(:cmd).with("sudo ip netns exec #{vm.inhost_name} bash -c '#{cmd}'")

      expect { nx.remove_cert_server }.to hop("remove_load_balancer")
    end
  end

  describe "#remove_load_balancer" do
    let(:vmh) {
      instance_double(VmHost, sshable: instance_double(Sshable))
    }

    before do
      allow(vm).to receive(:vm_host).and_return(vmh)
      allow(vm.nics.first).to receive_messages(private_ipv4: NetAddr::IPv4Net.parse("192.168.1.0/32"), private_ipv6: NetAddr::IPv6Net.parse("fd10:9b0b:6b4b:8fbb::/64"))
    end

    it "creates basic nat rules" do
      expect(vmh.sshable).to receive(:cmd).with("sudo ip netns exec #{vm.inhost_name} nft --file -", stdin: <<REMOVE_LOAD_BALANCER)
table ip nat;
delete table ip nat;
table inet nat;
delete table inet nat;
table ip nat {
  chain prerouting {
    type nat hook prerouting priority dstnat; policy accept;
    ip daddr 100.100.100.100/32 dnat to 192.168.1.0
  }
  chain postrouting {
    type nat hook postrouting priority srcnat; policy accept;
    ip saddr 192.168.1.0 ip daddr != { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } snat to 100.100.100.100/32
    ip saddr 192.168.1.0 ip daddr 192.168.1.0 snat to 100.100.100.100/32
  }
}
REMOVE_LOAD_BALANCER
      expect { nx.remove_load_balancer }.to exit({"msg" => "load balancer is updated"})
    end

    it "does not do anything if the VM is destroyed" do
      expect(nx).to receive(:vm).and_return(nil)

      expect { nx.remove_load_balancer }.to exit({"msg" => "load balancer is updated"})
    end
  end

  it "returns load_balancer" do
    expect(nx).to receive(:load_balancer).and_call_original
    expect(nx.load_balancer.id).to eq(lb.id)
  end
end
