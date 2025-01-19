pub mod shared_types;
pub mod rental_registry;
pub mod rental_agreement;

// Re-export public types from shared_types
pub use shared_types::{Property, PropertyDetails, AgreementDetails, RentalAgreement, AgreementStatus};

#[cfg(rental_registry)]
pub mod rental_registry_contract {
    pub use super::rental_registry::RentalRegistry;
}

#[cfg(rental_agreement)]
pub mod rental_agreement_contract {
    pub use super::rental_agreement::RentalAgreement;
}