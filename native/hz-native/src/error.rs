use crate::ffi::HzNativeStatus;

#[derive(Debug, Eq, PartialEq)]
pub enum NativeError {
    InvalidArgument(&'static str),
    InvalidArgumentMessage(String),
    #[allow(dead_code)]
    AllocationFailed(&'static str),
    #[allow(dead_code)]
    AllocationFailedMessage(String),
    Internal(&'static str),
    InternalMessage(String),
}

impl NativeError {
    pub fn status(&self) -> HzNativeStatus {
        match self {
            Self::InvalidArgument(_) | Self::InvalidArgumentMessage(_) => {
                HzNativeStatus::InvalidArgument
            }
            Self::AllocationFailed(_) | Self::AllocationFailedMessage(_) => {
                HzNativeStatus::AllocationFailed
            }
            Self::Internal(_) | Self::InternalMessage(_) => HzNativeStatus::InternalError,
        }
    }

    pub fn message_text(&self) -> String {
        match self {
            Self::InvalidArgument(message)
            | Self::AllocationFailed(message)
            | Self::Internal(message) => (*message).to_string(),
            Self::InvalidArgumentMessage(message)
            | Self::AllocationFailedMessage(message)
            | Self::InternalMessage(message) => message.clone(),
        }
    }
}
