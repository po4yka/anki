use generator::GeneratorError;
use llm::LlmError;
use std::error::Error;

common::assert_send_sync!(GeneratorError);

#[test]
fn generator_error_implements_error_trait() {
    let err = GeneratorError::Validation {
        message: "test".to_string(),
    };
    let _: &dyn Error = &err;
}

#[test]
fn llm_error_converts_to_generator_error() {
    let llm_err = LlmError::Connection("refused".to_string());
    let gen_err: GeneratorError = llm_err.into();
    assert!(gen_err.to_string().contains("connection"));
}
