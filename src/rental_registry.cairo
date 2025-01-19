use starknet::{ContractAddress, get_caller_address};
use core::traits::Into;
use core::starknet::event::Event;
use starknet::storage_access::StorageAccess;
use starknet::storage_access::StorageBaseImpl;
use starknet::storage_access::{Store, StorageMapMemberAccess, StorageMapMemberAccessImpl};

use super::shared_types::{Property, PropertyDetails};

#[starknet::interface]
pub trait IRentalRegistry<TContractState> {
    fn initialize(ref self: TContractState, admin: ContractAddress);
    fn create_property(ref self: TContractState, property_details: PropertyDetails);
    fn update_property_availability(ref self: TContractState, property_id: u256, is_available: bool);
    fn get_property(self: @TContractState, property_id: u256) -> Property;
    fn get_property_owner(self: @TContractState, property_id: u256) -> ContractAddress;
}

#[starknet::contract]
pub mod RentalRegistry {
    use starknet::{ContractAddress, get_caller_address};
    use core::traits::Into;
    use super::super::shared_types::{Property, PropertyDetails};
    use starknet::storage_access::StorageAccess;
    use starknet::storage_access::StorageBaseImpl;
    use starknet::storage_access::{Store, StorageMapMemberAccess, StorageMapMemberAccessImpl};

    #[storage]
    struct Storage {
        admin: ContractAddress,
        properties: Map::<u256, Property>,
        next_property_id: u256,
        property_to_owner: Map::<u256, ContractAddress>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        PropertyCreated: PropertyCreated,
        PropertyAvailabilityUpdated: PropertyAvailabilityUpdated,
    }

    #[derive(Drop, starknet::Event)]
    struct PropertyCreated {
        #[key]
        property_id: u256,
        owner: ContractAddress,
        price_per_month: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct PropertyAvailabilityUpdated {
        #[key]
        property_id: u256,
        is_available: bool,
    }

    #[constructor]
    fn constructor(ref self: ContractState, admin: ContractAddress) {
        self.admin.write(admin);
        self.next_property_id.write(1_u256);
    }

    #[abi(embed_v0)]
    impl RentalRegistryImpl of super::IRentalRegistry<ContractState> {
        fn initialize(ref self: ContractState, admin: ContractAddress) {
            let caller = get_caller_address();
            assert(self.admin.read() == caller, 'Only admin can initialize');
            self.admin.write(admin);
        }

        fn create_property(ref self: ContractState, property_details: PropertyDetails) {
            let caller = get_caller_address();
            let property_id = self.next_property_id.read();
            
            let property = Property {
                id: property_id,
                owner: caller,
                price_per_month: property_details.price_per_month,
                security_deposit: property_details.security_deposit,
                payment_token: property_details.payment_token,
                is_available: true,
                location_hash: property_details.location_hash,
            };

            self.properties.write(property_id, property);
            self.property_to_owner.write(property_id, caller);
            self.next_property_id.write(property_id + 1_u256);

            self.emit(PropertyCreated { 
                property_id, 
                owner: caller, 
                price_per_month: property_details.price_per_month 
            });
        }

        fn update_property_availability(
            ref self: ContractState, 
            property_id: u256, 
            is_available: bool
        ) {
            let mut property = self.properties.read(property_id);
            let caller = get_caller_address();
            
            // Make a copy of property to modify
            let mut updated_property = Property {
                is_available,
                ..property
            };
            
            assert(property.owner == caller, 'Only owner can update');
            self.properties.write(property_id, updated_property);

            self.emit(PropertyAvailabilityUpdated { property_id, is_available });
        }

        fn get_property(self: @ContractState, property_id: u256) -> Property {
            self.properties.read(property_id)
        }

        fn get_property_owner(self: @ContractState, property_id: u256) -> ContractAddress {
            self.property_to_owner.read(property_id)
        }
    }
}