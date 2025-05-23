# frozen_string_literal: true

class Clover
  def firewall_list_dataset
    dataset_authorize(@project.firewalls_dataset, "Firewall:view")
  end

  def firewall_list_api_response(dataset)
    dataset = dataset.where(location_id: @location.id) if @location
    result = dataset.eager(:firewall_rules).paginated_result(
      start_after: request.params["start_after"],
      page_size: request.params["page_size"],
      order_column: request.params["order_column"]
    )

    {
      items: Serializers::Firewall.serialize(result[:records]),
      count: result[:count]
    }
  end

  def firewall_post(firewall_name)
    authorize("Firewall:create", @project.id)
    Validation.validate_name(firewall_name)

    description = request.params["description"] || ""

    firewall = Firewall.create_with_id(
      name: firewall_name,
      description:,
      location_id: @location.id,
      project_id: @project.id
    )

    if api?
      Serializers::Firewall.serialize(firewall)
    else
      private_subnet = PrivateSubnet.from_ubid(request.params["private_subnet_id"])
      firewall.associate_with_private_subnet(private_subnet) if private_subnet

      flash["notice"] = "'#{firewall_name}' is created"
      request.redirect "#{@project.path}#{firewall.path}"
    end
  end

  def generate_firewall_options
    options = OptionTreeGenerator.new
    options.add_option(name: "name")
    options.add_option(name: "description")
    options.add_option(name: "location", values: Option.locations)
    subnets = dataset_authorize(@project.private_subnets_dataset, "PrivateSubnet:view").map {
      {
        location_id: it.location_id,
        value: it.ubid,
        display_name: it.name
      }
    }
    options.add_option(name: "private_subnet_id", values: subnets, parent: "location") do |location, private_subnet|
      private_subnet[:location_id] == location.id
    end
    options.serialize
  end
end
