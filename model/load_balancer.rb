# frozen_string_literal: true

require_relative "../model"

class LoadBalancer < Sequel::Model
  many_to_many :vms
  many_to_many :active_vms, class: :Vm, left_key: :load_balancer_id, right_key: :vm_id, join_table: :load_balancers_vms, conditions: { state: "healthy" }
  one_to_one :strand, key: :id

  include ResourceMethods
  include SemaphoreMethods
  include Authorization::TaggableMethods
  include Authorization::HyperTagMethods
  semaphore :destroy, :update_load_balancer, :rewrite_dns_records

  def hyper_tag_name(project)
    "project/#{project.ubid}/load-balancer/#{name}"
  end

  dataset_module Pagination
  dataset_module Authorization::Dataset

  def path
    "/load-balancer/#{name}"
  end

  def vm_lb_state(vm)
    DB[:load_balancers_vms].where(load_balancer_id: id, vm_id: vm.id).first[:state]
  end

  def hostname
    "#{name}.#{ubid[-5...]}.#{Config.load_balancer_service_hostname}"
  end
end
