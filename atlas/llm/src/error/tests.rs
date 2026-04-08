use super::*;
use std::error::Error;

common::assert_send_sync!(LlmError);

#[test]
fn error_is_std_error() {
    let err = LlmError::Connection("test".to_string());
    let _: &dyn Error = &err;
}

#[test]
fn invalid_json_preserves_response_text() {
    let err = LlmError::InvalidJson {
        message: "bad".to_string(),
        response_text: "raw response here".to_string(),
    };
    if let LlmError::InvalidJson { response_text, .. } = &err {
        assert_eq!(response_text, "raw response here");
    } else {
        panic!("wrong variant");
    }
}

#[test]
fn error_debug_format() {
    let err = LlmError::Http {
        status: 500,
        body: "internal".to_string(),
    };
    let debug = format!("{:?}", err);
    assert!(debug.contains("Http"));
    assert!(debug.contains("500"));
}
