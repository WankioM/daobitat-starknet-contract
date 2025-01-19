use starknet::ContractAddress;
use starknet::storage_access::StorePacking;

// Make all structs and enums public with 'pub'
#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct PropertyDetails {
    pub price_per_month: u256,
    pub security_deposit: u256,
    pub payment_token: ContractAddress,
    pub location_hash: felt252,
}

#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct Property {
    pub id: u256,
    pub owner: ContractAddress,
    pub price_per_month: u256,
    pub security_deposit: u256,
    pub payment_token: ContractAddress,
    pub is_available: bool,
    pub location_hash: felt252,
}

#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct AgreementDetails {
    pub start_date: u64,
    pub end_date: u64,
}

#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct RentalAgreement {
    pub id: u256,
    pub property_id: u256,
    pub tenant: ContractAddress,
    pub landlord: ContractAddress,
    pub start_date: u64,
    pub end_date: u64,
    pub rent_amount: u256,
    pub security_deposit: u256,
    pub payment_token: ContractAddress,
    pub status: AgreementStatus,
    pub last_payment_date: u64,
    pub next_payment_date: u64,
}

#[derive(Copy, Drop, Serde, starknet::Store, PartialEq)]
pub enum AgreementStatus {
    Pending: (),
    Active: (),
    Terminated: (),
    Completed: (),
    Disputed: ()
}