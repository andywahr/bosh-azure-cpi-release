# frozen_string_literal: true

require 'spec_helper'
require 'unit/vm_manager/create/shared_stuff.rb'

describe Bosh::AzureCloud::VMManager do
  include_context 'shared stuff for vm manager'

  # The following variables are defined in shared_stuff.rb. You can override it if needed.
  #   - resource_group_name
  #   - default_security_group
  describe '#create' do
    context 'when VM is created' do
      before do
        allow(client2).to receive(:create_virtual_machine)
      end

      # Network Security Group
      context '#network_security_group' do
        context 'when the network security group is not specified in the global configuration' do
          let(:azure_config_without_default_security_group) do
            mock_azure_config_merge(
              'default_security_group' => nil
            )
          end
          let(:vm_manager_without_default_security_group) do
            Bosh::AzureCloud::VMManager.new(
              azure_config_without_default_security_group, registry_endpoint, disk_manager, disk_manager2, client2, storage_account_manager
            )
          end

          it 'should not assign network security group to the network interface' do
            expect(client2).not_to receive(:delete_virtual_machine)
            expect(client2).not_to receive(:delete_network_interface)
            expect(client2).to receive(:create_network_interface)
              .with(resource_group_name, hash_including(network_security_group: nil), any_args).twice
            expect do
              vm_manager_without_default_security_group.create(instance_id, location, stemcell_info, vm_properties, network_configurator, env)
            end.not_to raise_error
          end

          context 'when the network security group is an empty string in the global configuration' do
            let(:azure_config_without_default_security_group) do
              mock_azure_config_merge(
                'default_security_group' => ''
              )
            end
            let(:vm_manager_without_default_security_group) do
              Bosh::AzureCloud::VMManager.new(
                azure_config_without_default_security_group, registry_endpoint, disk_manager, disk_manager2, client2, storage_account_manager
              )
            end

            it 'should raise an error' do
              expect(client2).not_to receive(:get_network_security_group_by_name)
              expect(client2).not_to receive(:create_network_interface)
              expect(client2).to receive(:list_network_interfaces_by_keyword).and_return([])
              expect(client2).not_to receive(:delete_network_interface)
              expect(client2).not_to receive(:delete_virtual_machine)
              expect do
                vm_manager_without_default_security_group.create(instance_id, location, stemcell_info, vm_properties, network_configurator, env)
              end.to raise_error /Cannot specify an empty string to the network security group/
            end
          end

          context 'when the network security group is specified in the global configuration' do
            it 'should assign the default network security group to the network interface' do
              expect(client2).not_to receive(:delete_virtual_machine)
              expect(client2).not_to receive(:delete_network_interface)
              expect(client2).to receive(:create_network_interface)
                .with(resource_group_name, hash_including(network_security_group: default_security_group), any_args).twice
              expect do
                vm_manager.create(instance_id, location, stemcell_info, vm_properties, network_configurator, env)
              end.not_to raise_error
            end

            context ' and network specs' do
              let(:nsg_name_in_network_spec) { 'fake-nsg-name-specified-in-network-spec' }
              let(:security_group_in_network_spec) do
                {
                  name: nsg_name_in_network_spec
                }
              end

              before do
                allow(manual_network).to receive(:security_group).and_return(nsg_name_in_network_spec)
                allow(dynamic_network).to receive(:security_group).and_return(nsg_name_in_network_spec)
                allow(client2).to receive(:get_network_security_group_by_name)
                  .with(MOCK_RESOURCE_GROUP_NAME, nsg_name_in_network_spec)
                  .and_return(security_group_in_network_spec)
              end

              it 'should assign the network security group specified in network specs to the network interface' do
                expect(client2).not_to receive(:delete_virtual_machine)
                expect(client2).not_to receive(:delete_network_interface)
                expect(client2).to receive(:create_network_interface)
                  .with(resource_group_name, hash_including(network_security_group: security_group_in_network_spec), any_args).twice
                expect(client2).not_to receive(:create_network_interface)
                  .with(resource_group_name, hash_including(network_security_group: default_security_group), any_args)
                expect do
                  vm_manager.create(instance_id, location, stemcell_info, vm_properties, network_configurator, env)
                end.not_to raise_error
              end

              context ' and vm_properties' do
                let(:nsg_name_in_vm_properties) { 'fake-nsg-name-specified-in-resource-pool' }
                let(:security_group_in_vm_properties) do
                  {
                    name: nsg_name_in_vm_properties
                  }
                end
                let(:vm_properties) do
                  {
                    'instance_type'  => 'Standard_D1',
                    'security_group' => nsg_name_in_vm_properties
                  }
                end

                before do
                  allow(client2).to receive(:get_network_security_group_by_name)
                    .with(MOCK_RESOURCE_GROUP_NAME, nsg_name_in_vm_properties)
                    .and_return(security_group_in_vm_properties)
                end

                it 'should assign the network security group specified in vm_types or vm_extensions to the network interface' do
                  expect(client2).not_to receive(:delete_virtual_machine)
                  expect(client2).not_to receive(:delete_network_interface)
                  expect(client2).to receive(:create_network_interface)
                    .with(resource_group_name, hash_including(network_security_group: security_group_in_vm_properties), any_args).twice
                  expect(client2).not_to receive(:create_network_interface)
                    .with(resource_group_name, hash_including(network_security_group: security_group_in_network_spec), any_args)
                  expect(client2).not_to receive(:create_network_interface)
                    .with(resource_group_name, hash_including(network_security_group: default_security_group), any_args)
                  expect do
                    vm_manager.create(instance_id, location, stemcell_info, vm_properties, network_configurator, env)
                  end.not_to raise_error
                end
              end
            end
          end
        end

        # The cases in the below context doesn't care where the nsg name is specified.
        context '#resource_group_for_network_security_group' do
          let(:nsg_name) { 'fake-nsg-name' }
          let(:security_group) do
            {
              name: nsg_name
            }
          end
          let(:vm_properties) do
            {
              'instance_type'  => 'Standard_D1',
              'security_group' => nsg_name
            }
          end

          context 'when the resource group name is specified in the global configuration' do
            before do
              allow(manual_network).to receive(:resource_group_name).and_return(MOCK_RESOURCE_GROUP_NAME)
              allow(dynamic_network).to receive(:resource_group_name).and_return(MOCK_RESOURCE_GROUP_NAME)
              allow(client2).to receive(:get_network_subnet_by_name)
                .with(MOCK_RESOURCE_GROUP_NAME, 'fake-virtual-network-name', 'fake-subnet-name')
                .and_return(subnet)
            end

            it 'should find the network security group in the default resource group' do
              expect(client2).not_to receive(:delete_virtual_machine)
              expect(client2).not_to receive(:delete_network_interface)
              expect(client2).to receive(:get_network_security_group_by_name)
                .with(MOCK_RESOURCE_GROUP_NAME, nsg_name)
                .and_return(security_group).twice
              expect(client2).to receive(:create_network_interface)
                .with(resource_group_name, hash_including(network_security_group: security_group), any_args).twice
              expect do
                vm_manager.create(instance_id, location, stemcell_info, vm_properties, network_configurator, env)
              end.not_to raise_error
            end
          end

          context 'when the resource group name is specified in the network spec' do
            let(:rg_name_for_nsg) { 'resource-group-name-for-network-security-group' }
            before do
              allow(manual_network).to receive(:resource_group_name).and_return(rg_name_for_nsg)
              allow(dynamic_network).to receive(:resource_group_name).and_return(rg_name_for_nsg)
              allow(client2).to receive(:get_network_subnet_by_name)
                .with(rg_name_for_nsg, 'fake-virtual-network-name', 'fake-subnet-name')
                .and_return(subnet)
            end

            context 'when network security group is found in the specified resource group' do
              before do
                allow(instance_id).to receive(:resource_group_name).and_return(rg_name_for_nsg)
              end

              it 'should assign the security group to the network interface' do
                expect(client2).not_to receive(:delete_virtual_machine)
                expect(client2).not_to receive(:delete_network_interface)
                expect(client2).to receive(:get_network_security_group_by_name)
                  .with(rg_name_for_nsg, nsg_name)
                  .and_return(security_group).twice
                expect(client2).not_to receive(:get_network_security_group_by_name)
                  .with(MOCK_RESOURCE_GROUP_NAME, nsg_name)
                expect(client2).to receive(:create_network_interface)
                  .with(rg_name_for_nsg, hash_including(network_security_group: security_group), any_args).twice
                expect do
                  vm_manager.create(instance_id, location, stemcell_info, vm_properties, network_configurator, env)
                end.not_to raise_error
              end
            end

            context 'when network security group is not found in the specified resource group, but found in the default resource group' do
              it 'should assign the security group to the network interface' do
                expect(client2).not_to receive(:delete_virtual_machine)
                expect(client2).not_to receive(:delete_network_interface)
                expect(client2).to receive(:get_network_security_group_by_name)
                  .with(rg_name_for_nsg, nsg_name)
                  .and_return(nil).twice
                expect(client2).to receive(:get_network_security_group_by_name)
                  .with(MOCK_RESOURCE_GROUP_NAME, nsg_name)
                  .and_return(security_group).twice
                expect(client2).to receive(:create_network_interface)
                  .with(resource_group_name, hash_including(network_security_group: security_group), any_args).twice
                expect do
                  vm_manager.create(instance_id, location, stemcell_info, vm_properties, network_configurator, env)
                end.not_to raise_error
              end
            end

            context 'when network security group is not found in neither the specified resource group nor the default resource group' do
              it 'should raise an error' do
                expect(client2).not_to receive(:delete_virtual_machine)
                expect(client2).not_to receive(:delete_network_interface)
                expect(client2).to receive(:get_network_security_group_by_name)
                  .with(rg_name_for_nsg, nsg_name)
                  .and_return(nil)
                expect(client2).to receive(:get_network_security_group_by_name)
                  .with(MOCK_RESOURCE_GROUP_NAME, nsg_name)
                  .and_return(nil)
                expect(client2).not_to receive(:create_network_interface)
                expect(client2).to receive(:list_network_interfaces_by_keyword).and_return([])
                expect(client2).not_to receive(:delete_network_interface)
                expect do
                  vm_manager.create(instance_id, location, stemcell_info, vm_properties, network_configurator, env)
                end.to raise_error /Cannot find the network security group '#{nsg_name}'/
              end
            end
          end
        end
      end
    end
  end
end
