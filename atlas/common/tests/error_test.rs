use common::error::*;
use std::collections::HashMap;
use std::error::Error;

// ── Send + Sync ──────────────────────────────────────────────────────────

common::assert_send_sync!(AnkiAtlasError);

// ── Display / Error trait ────────────────────────────────────────────────

#[test]
fn error_implements_std_error() {
    let err = AnkiAtlasError::DatabaseConnection {
        message: "timeout".to_string(),
        context: HashMap::new(),
    };
    let _: &dyn Error = &err;
}

// ── ErrorContext ─────────────────────────────────────────────────────────

#[test]
fn error_carries_context() {
    let mut ctx = HashMap::new();
    ctx.insert("host".to_string(), "localhost".to_string());
    ctx.insert("port".to_string(), "5432".to_string());

    let err = AnkiAtlasError::DatabaseConnection {
        message: "refused".to_string(),
        context: ctx,
    };

    // Context is accessible but not in Display
    assert!(!err.to_string().contains("host"));
    if let AnkiAtlasError::DatabaseConnection { context, .. } = &err {
        assert_eq!(context.get("host").unwrap(), "localhost");
        assert_eq!(context.get("port").unwrap(), "5432");
    } else {
        panic!("wrong variant");
    }
}

#[test]
fn error_empty_context() {
    let err = AnkiAtlasError::Embedding {
        message: "fail".to_string(),
        context: HashMap::new(),
    };
    if let AnkiAtlasError::Embedding { context, .. } = &err {
        assert!(context.is_empty());
    }
}

// ── Result type alias ───────────────────────────────────────────────────

#[test]
fn result_alias_works() {
    fn ok_fn() -> Result<i32> {
        Ok(42)
    }
    fn err_fn() -> Result<i32> {
        Err(AnkiAtlasError::NotFound {
            message: "nope".to_string(),
            context: HashMap::new(),
        })
    }
    assert!(ok_fn().is_ok());
    assert!(err_fn().is_err());
}

// ── WithContext trait ────────────────────────────────────────────────────

#[test]
fn with_context_adds_key_value() {
    let err = AnkiAtlasError::DatabaseConnection {
        message: "timeout".to_string(),
        context: HashMap::new(),
    };
    let err = err.with_context("host", "db.example.com");
    if let AnkiAtlasError::DatabaseConnection { context, .. } = &err {
        assert_eq!(context.get("host").unwrap(), "db.example.com");
    } else {
        panic!("wrong variant");
    }
}

#[test]
fn with_context_chains() {
    let err = AnkiAtlasError::Embedding {
        message: "fail".to_string(),
        context: HashMap::new(),
    }
    .with_context("model", "ada-002")
    .with_context("provider", "openai");

    if let AnkiAtlasError::Embedding { context, .. } = &err {
        assert_eq!(context.get("model").unwrap(), "ada-002");
        assert_eq!(context.get("provider").unwrap(), "openai");
    } else {
        panic!("wrong variant");
    }
}

#[test]
fn with_context_on_variant_without_context_is_noop() {
    // DimensionMismatch has no ErrorContext field
    let err = AnkiAtlasError::DimensionMismatch {
        collection: "notes".to_string(),
        expected: 1536,
        actual: 768,
    };
    // Should return self unchanged (no panic)
    let err = err.with_context("key", "value");
    assert_eq!(
        err.to_string(),
        "dimension mismatch on 'notes': expected 1536, got 768"
    );
}

#[test]
fn with_context_on_embedding_model_changed_is_noop() {
    let err = AnkiAtlasError::EmbeddingModelChanged {
        stored: "old".to_string(),
        current: "new".to_string(),
    };
    let err = err.with_context("key", "value");
    assert!(err.to_string().contains("old"));
}

// ── Debug impl ──────────────────────────────────────────────────────────

#[test]
fn all_variants_implement_debug() {
    let _ = format!(
        "{:?}",
        AnkiAtlasError::DatabaseConnection {
            message: "x".to_string(),
            context: HashMap::new(),
        }
    );
    let _ = format!(
        "{:?}",
        AnkiAtlasError::DimensionMismatch {
            collection: "c".to_string(),
            expected: 1,
            actual: 2,
        }
    );
    let _ = format!(
        "{:?}",
        AnkiAtlasError::EmbeddingModelChanged {
            stored: "a".to_string(),
            current: "b".to_string(),
        }
    );
}

// ── Re-exports from crate root ──────────────────────────────────────────

#[test]
fn crate_root_reexports_error_types() {
    // These should be accessible from common::AnkiAtlasError and common::Result
    let _: common::Result<()> = Ok(());
    let _err = common::AnkiAtlasError::NotFound {
        message: "test".to_string(),
        context: HashMap::new(),
    };
}
