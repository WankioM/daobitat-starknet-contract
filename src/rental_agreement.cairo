use starknet::{ContractAddress, get_caller_address, get_contract_address, get_block_timestamp};
use core::array::ArrayTrait;
use core::traits::Into;
use core::option::OptionTrait;
use starknet::storage_access::StorageAccess;
use starknet::storage_access::StorageBaseImpl;
use starknet::storage_access::{Store, StorageMapMemberAccess, StorageMapMemberAccessImpl};
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use super::shared_types::{RentalAgreement, AgreementDetails, AgreementStatus, Property};
use super::rental_registry::{IRentalRegistryDispatcher, IRentalRegistryDispatcherTrait};

const SECONDS_PER_DAY: u64 = 86400_u64;
const DEFAULT_DISPUTE_PERIOD: u64 = 3 * SECONDS_PER_DAY;
const BASIS_POINTS: u256 = 10000_u256;

#[derive(Copy, Drop, Serde, starknet::Store)]
struct PaymentHistory {
    total_paid: u256,
    number_of_payments: u256,
    security_deposit_paid: bool,
    last_payment_timestamp: u64,
}

#[derive(Copy, Drop, Serde, starknet::Store)]
enum PaymentType {
    SecurityDeposit: (),
    Rent: (),
    Fee: ()
}

#[derive(Copy, Drop, Serde, starknet::Store, PartialEq)]
enum EscrowStatus {
    Pending: (),
    Funded: (),
    Released: (),
    Disputed: (),
    Refunded: ()
}

#[derive(Copy, Drop, Serde, starknet::Store)]
struct EscrowDetails {
    status: EscrowStatus,
    amount: u256,
    release_timestamp: u64,
    tenant_confirmed: bool,
    dispute_deadline: u64,
    disputed_by_landlord: bool,
    disputed_by_tenant: bool,
}

#[starknet::interface]
trait IRentalAgreement<TContractState> {
    fn initialize(
        ref self: TContractState, 
        admin: ContractAddress, 
        registry: ContractAddress,
        platform_fee_bps: u256
    );
    fn create_agreement(
        ref self: TContractState,
        property_id: u256,
        agreement_details: AgreementDetails
    );
    fn fund_escrow(ref self: TContractState, agreement_id: u256, amount: u256);
    fn confirm_move_in(ref self: TContractState, agreement_id: u256);
    fn raise_dispute(ref self: TContractState, agreement_id: u256);
    fn release_escrow_funds(ref self: TContractState, agreement_id: u256);
    fn get_agreement(self: @TContractState, agreement_id: u256) -> RentalAgreement;
}

#[starknet::contract]
mod RentalAgreement {
    use super::*;
    use starknet::Event;
    use core::starknet::event::EventEmitter;
    use starknet::storage_access::StorageAccess;
    use starknet::storage_access::StorageBaseImpl;
    use starknet::storage_access::{Store, StorageMapMemberAccess, StorageMapMemberAccessImpl};

    #[storage]
    struct Storage {
        admin: ContractAddress,
        registry: IRentalRegistryDispatcher,
        platform_fee_bps: u256,
        dispute_period: u64,
        agreement_escrows: Map::<u256, EscrowDetails>,
        escrow_tokens: Map::<u256, ContractAddress>,
        agreements: Map::<u256, RentalAgreement>,
        next_agreement_id: u256,
        property_to_agreements: Map::<u256, Array<u256>>,
        tenant_to_agreements: Map::<ContractAddress, Array<u256>>,
        agreement_payments: Map::<u256, PaymentHistory>
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        AgreementCreated: AgreementCreated,
        PaymentProcessed: PaymentProcessed,
        EscrowFunded: EscrowFunded,
        EscrowReleased: EscrowReleased,
        DisputeRaised: DisputeRaised,
        TenantConfirmed: TenantConfirmed,
    }

    #[derive(Drop, starknet::Event)]
    struct AgreementCreated {
        #[key]
        agreement_id: u256,
        property_id: u256,
        tenant: ContractAddress,
        landlord: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct PaymentProcessed {
        #[key]
        agreement_id: u256,
        amount: u256,
        payment_type: PaymentType,
    }

    #[derive(Drop, starknet::Event)]
    struct EscrowFunded {
        #[key]
        agreement_id: u256,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct EscrowReleased {
        #[key]
        agreement_id: u256,
        amount: u256,
        fee: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct DisputeRaised {
        #[key]
        agreement_id: u256,
        raised_by: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct TenantConfirmed {
        #[key]
        agreement_id: u256,
        tenant: ContractAddress,
        timestamp: u64,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        admin: ContractAddress,
        registry: ContractAddress,
        platform_fee_bps: u256
    ) {
        assert(platform_fee_bps <= BASIS_POINTS, 'Fee bps must be <= 10000');
        self.admin.write(admin);
        self.registry.write(IRentalRegistryDispatcher { contract_address: registry });
        self.platform_fee_bps.write(platform_fee_bps);
        self.next_agreement_id.write(1_u256);
        self.dispute_period.write(DEFAULT_DISPUTE_PERIOD);
    }

    #[generate_trait]
    impl StorageAccess of StorageAccessTrait {
        fn get_agreement(self: @ContractState, id: u256) -> RentalAgreement {
            self.agreements.read(id)
        }

        fn get_escrow(self: @ContractState, id: u256) -> EscrowDetails {
            self.agreement_escrows.read(id)
        }

        fn set_agreement(ref self: ContractState, id: u256, agreement: RentalAgreement) {
            self.agreements.write(id, agreement);
        }

        fn set_escrow(ref self: ContractState, id: u256, escrow: EscrowDetails) {
            self.agreement_escrows.write(id, escrow);
        }

        fn is_admin(self: @ContractState, address: ContractAddress) -> bool {
            self.admin.read() == address
        }
    }

    #[abi(embed_v0)]
    impl RentalAgreementImpl of super::IRentalAgreement<ContractState> {
        fn initialize(
            ref self: ContractState,
            admin: ContractAddress,
            registry: ContractAddress,
            platform_fee_bps: u256
        ) {
            let caller = get_caller_address();
            assert(self.admin.read() == caller, 'Only admin can initialize');
            assert(platform_fee_bps <= BASIS_POINTS, 'Fee bps must be <= 10000');
            self.admin.write(admin);
            self.registry.write(IRentalRegistryDispatcher { contract_address: registry });
            self.platform_fee_bps.write(platform_fee_bps);
        }

        fn create_agreement(
            ref self: ContractState,
            property_id: u256,
            agreement_details: AgreementDetails
        ) {
            let caller = get_caller_address();
            
            // Get property from registry
            let property = self.registry.read().get_property(property_id);
            assert(property.is_available, 'Property not available');
            
            assert(
                agreement_details.start_date < agreement_details.end_date,
                'Invalid dates'
            );
            
            let agreement_id = self.next_agreement_id.read();
            
            let agreement = RentalAgreement {
                id: agreement_id,
                property_id,
                tenant: caller,
                landlord: property.owner,
                start_date: agreement_details.start_date,
                end_date: agreement_details.end_date,
                rent_amount: property.price_per_month,
                security_deposit: property.security_deposit,
                payment_token: property.payment_token,
                status: AgreementStatus::Pending,
                last_payment_date: 0,
                next_payment_date: agreement_details.start_date,
            };

            // Save agreement
            self.set_agreement(agreement_id, agreement);
            
            // Update property availability in registry
            self.registry.read().update_property_availability(property_id, false);
            
            // Update counters and mappings
            self.next_agreement_id.write(agreement_id + 1_u256);
            
            let mut property_agreements = self.property_to_agreements.read(property_id);
            property_agreements.append(agreement_id);
            self.property_to_agreements.write(property_id, property_agreements);
            
            let mut tenant_agreements = self.tenant_to_agreements.read(caller);
            tenant_agreements.append(agreement_id);
            self.tenant_to_agreements.write(caller, tenant_agreements);
            
            // Initialize payment history
            let payment_history = PaymentHistory {
                total_paid: 0_u256,
                number_of_payments: 0_u256,
                security_deposit_paid: false,
                last_payment_timestamp: 0,
            };
            self.agreement_payments.write(agreement_id, payment_history);

            // Emit event
            self.emit(AgreementCreated {
                agreement_id,
                property_id,
                tenant: caller,
                landlord: property.owner,
            });
        }

        fn fund_escrow(ref self: ContractState, agreement_id: u256, amount: u256) {
            let caller = get_caller_address();
            let agreement = self.get_agreement(agreement_id);
            assert(agreement.tenant == caller, 'Only tenant can fund escrow');
            
            let current_timestamp = get_block_timestamp();
            let dispute_deadline = current_timestamp + self.dispute_period.read();
            
            let escrow = EscrowDetails {
                status: EscrowStatus::Funded,
                amount,
                release_timestamp: current_timestamp,
                tenant_confirmed: false,
                dispute_deadline,
                disputed_by_landlord: false,
                disputed_by_tenant: false,
            };
            
            // Transfer tokens to contract
            let token = IERC20Dispatcher { contract_address: agreement.payment_token };
            token.transfer_from(caller, get_contract_address(), amount);
            
            // Save escrow details
            self.set_escrow(agreement_id, escrow);
            self.escrow_tokens.write(agreement_id, agreement.payment_token);
            
            self.emit(EscrowFunded { agreement_id, amount });
        }

        fn confirm_move_in(ref self: ContractState, agreement_id: u256) {
            let caller = get_caller_address();
            let agreement = self.get_agreement(agreement_id);
            assert(agreement.tenant == caller, 'Only tenant can confirm');
            
            let escrow = self.get_escrow(agreement_id);
            assert(escrow.status == EscrowStatus::Funded, 'Escrow not funded');
            
            // Update escrow
            let new_escrow = EscrowDetails {
                tenant_confirmed: true,
                ..escrow
            };
            self.set_escrow(agreement_id, new_escrow);
            
            // Update agreement status
            let updated_agreement = RentalAgreement {
                status: AgreementStatus::Active,
                ..agreement
            };
            self.set_agreement(agreement_id, updated_agreement);
            
            self.emit(TenantConfirmed { 
                agreement_id,
                tenant: caller,
                timestamp: get_block_timestamp()
            });
            
            // Release funds if dispute period has ended
            if get_block_timestamp() > escrow.dispute_deadline {
                self.release_escrow_funds(agreement_id);
            }
        }

        fn raise_dispute(ref self: ContractState, agreement_id: u256) {
            let caller = get_caller_address();
            let agreement = self.get_agreement(agreement_id);
            let escrow = self.get_escrow(agreement_id);
            
            assert(
                caller == agreement.tenant || caller == agreement.landlord,
                'Not authorized'
            );
            
            assert(
                get_block_timestamp() <= escrow.dispute_deadline,
                'Dispute period ended'
            );
            
            // Update escrow with dispute status
            let new_escrow = EscrowDetails {
                status: EscrowStatus::Disputed,
                disputed_by_tenant: if caller == agreement.tenant { true } else { escrow.disputed_by_tenant },
                disputed_by_landlord: if caller == agreement.landlord { true } else { escrow.disputed_by_landlord },
                ..escrow
            };
            self.set_escrow(agreement_id, new_escrow);
            
            // Update agreement status
            let updated_agreement = RentalAgreement {
                status: AgreementStatus::Disputed,
                ..agreement
            };
            self.set_agreement(agreement_id, updated_agreement);
            
            self.emit(DisputeRaised { 
                agreement_id,
                raised_by: caller
            });
        }

        fn release_escrow_funds(ref self: ContractState, agreement_id: u256) {
            let escrow = self.get_escrow(agreement_id);
            let agreement = self.get_agreement(agreement_id);
            
            // Verify release conditions
            assert(
                escrow.status == EscrowStatus::Funded &&
                (escrow.tenant_confirmed || get_block_timestamp() > escrow.dispute_deadline) &&
                !escrow.disputed_by_tenant &&
                !escrow.disputed_by_landlord,
                'Cannot release funds'
            );
            
            // Calculate fee and net amount
            let token = IERC20Dispatcher { 
                contract_address: self.escrow_tokens.read(agreement_id) 
            };
            
            let fee = (escrow.amount * self.platform_fee_bps.read()) / BASIS_POINTS;
            let net_amount = escrow.amount - fee;
            
            // Transfer funds
            token.transfer(agreement.landlord, net_amount);
            token.transfer(self.admin.read(), fee);
            
            // Update escrow status
            let new_escrow = EscrowDetails {
                status: EscrowStatus::Released,
                ..escrow
            };
            self.set_escrow(agreement_id, new_escrow);
            
            // Update payment history
            let mut payment_history = self.agreement_payments.read(agreement_id);
            payment_history.total_paid += escrow.amount;
            payment_history.number_of_payments += 1_u256;
            payment_history.security_deposit_paid = true;
            payment_history.last_payment_timestamp = get_block_timestamp();
            self.agreement_payments.write(agreement_id, payment_history);
            
            // Emit events
            self.emit(PaymentProcessed {
                agreement_id,
                amount: escrow.amount,
                payment_type: PaymentType::SecurityDeposit
            });
            
            self.emit(EscrowReleased { 
                agreement_id,
                amount: net_amount,
                fee
            });
        }

        fn get_agreement(self: @ContractState, agreement_id: u256) -> RentalAgreement {
            self.get_agreement(agreement_id)
        }
    }
}