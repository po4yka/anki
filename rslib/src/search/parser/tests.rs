// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

use super::ast::*;
use super::parse;
use crate::error::Result;
use crate::error::SearchErrorKind;

#[test]
fn parsing() -> Result<()> {
    use Node::*;
    use SearchNode::*;

    assert_eq!(parse("")?, vec![Search(WholeCollection)]);
    assert_eq!(parse("  ")?, vec![Search(WholeCollection)]);

    // leading/trailing/interspersed whitespace
    assert_eq!(
        parse("  t   t2  ")?,
        vec![
            Search(UnqualifiedText("t".into())),
            And,
            Search(UnqualifiedText("t2".into()))
        ]
    );

    // including in groups
    assert_eq!(
        parse("(  t   t2  )")?,
        vec![Group(vec![
            Search(UnqualifiedText("t".into())),
            And,
            Search(UnqualifiedText("t2".into()))
        ])]
    );

    assert_eq!(
        parse(r#"hello  -(world and "foo:bar baz") OR test"#)?,
        vec![
            Search(UnqualifiedText("hello".into())),
            And,
            Not(Box::new(Group(vec![
                Search(UnqualifiedText("world".into())),
                And,
                Search(SingleField {
                    field: "foo".into(),
                    text: "bar baz".into(),
                    mode: FieldSearchMode::Normal,
                })
            ]))),
            Or,
            Search(UnqualifiedText("test".into()))
        ]
    );

    assert_eq!(
        parse("foo:re:bar")?,
        vec![Search(SingleField {
            field: "foo".into(),
            text: "bar".into(),
            mode: FieldSearchMode::Regex,
        })]
    );

    assert_eq!(
        parse("foo:nc:bar")?,
        vec![Search(SingleField {
            field: "foo".into(),
            text: "bar".into(),
            mode: FieldSearchMode::NoCombining,
        })]
    );

    // escaping is independent of quotation
    assert_eq!(
        parse(r#""field:va\"lue""#)?,
        vec![Search(SingleField {
            field: "field".into(),
            text: "va\"lue".into(),
            mode: FieldSearchMode::Normal,
        })]
    );
    assert_eq!(parse(r#""field:va\"lue""#)?, parse(r#"field:"va\"lue""#)?,);
    assert_eq!(parse(r#""field:va\"lue""#)?, parse(r#"field:va\"lue"#)?,);

    // parser unescapes ":()-
    assert_eq!(
        parse(r#"\"\:\(\)\-"#)?,
        vec![Search(UnqualifiedText(r#"":()-"#.into())),]
    );

    // parser doesn't unescape unescape \*_
    assert_eq!(
        parse(r"\\\*\_")?,
        vec![Search(UnqualifiedText(r"\\\*\_".into())),]
    );

    // escaping parentheses is optional (only) inside quotes
    assert_eq!(parse(r#""\)\(""#), parse(r#"")(""#));

    // escaping : is optional if it is preceded by another :
    assert_eq!(parse("field:val:ue"), parse(r"field:val\:ue"));
    assert_eq!(parse(r#""field:val:ue""#), parse(r"field:val\:ue"));
    assert_eq!(parse(r#"field:"val:ue""#), parse(r"field:val\:ue"));

    // escaping - is optional if it cannot be mistaken for a negator
    assert_eq!(parse("-"), parse(r"\-"));
    assert_eq!(parse("A-"), parse(r"A\-"));
    assert_eq!(parse(r#""-A""#), parse(r"\-A"));
    assert_ne!(parse("-A"), parse(r"\-A"));

    // any character should be escapable on the right side of re:
    assert_eq!(
        parse(r#""re:\btest\%""#)?,
        vec![Search(Regex(r"\btest\%".into()))]
    );

    // no exceptions for escaping "
    assert_eq!(
        parse(r#"re:te\"st"#)?,
        vec![Search(Regex(r#"te"st"#.into()))]
    );

    // spaces are optional if node separation is clear
    assert_eq!(parse(r#"a"b"(c)"#)?, parse("a b (c)")?);

    assert_eq!(parse("added:3")?, vec![Search(AddedInDays(3))]);
    assert_eq!(
        parse("card:front")?,
        vec![Search(CardTemplate(TemplateKind::Name("front".into())))]
    );
    assert_eq!(
        parse("card:3")?,
        vec![Search(CardTemplate(TemplateKind::Ordinal(2)))]
    );
    // 0 must not cause a crash due to underflow
    assert_eq!(
        parse("card:0")?,
        vec![Search(CardTemplate(TemplateKind::Ordinal(0)))]
    );
    assert_eq!(parse("deck:default")?, vec![Search(Deck("default".into()))]);
    assert_eq!(
        parse("deck:\"default one\"")?,
        vec![Search(Deck("default one".into()))]
    );

    assert_eq!(
        parse("preset:default")?,
        vec![Search(Preset("default".into()))]
    );

    assert_eq!(parse("note:basic")?, vec![Search(Notetype("basic".into()))]);
    assert_eq!(
        parse("tag:hard")?,
        vec![Search(Tag {
            tag: "hard".into(),
            mode: FieldSearchMode::Normal
        })]
    );
    assert_eq!(
        parse(r"tag:re:\\")?,
        vec![Search(Tag {
            tag: r"\\".into(),
            mode: FieldSearchMode::Regex
        })]
    );
    assert_eq!(
        parse("nid:1237123712,2,3")?,
        vec![Search(NoteIds("1237123712,2,3".into()))]
    );
    assert_eq!(parse("is:due")?, vec![Search(State(StateKind::Due))]);
    assert_eq!(parse("flag:3")?, vec![Search(Flag(3))]);

    assert_eq!(
        parse("prop:ivl>3")?,
        vec![Search(Property {
            operator: ">".into(),
            kind: PropertyKind::Interval(3)
        })]
    );
    assert_eq!(
        parse("prop:ease<=3.3")?,
        vec![Search(Property {
            operator: "<=".into(),
            kind: PropertyKind::Ease(3.3)
        })]
    );
    assert_eq!(
        parse("prop:cdn:abc<=1")?,
        vec![Search(Property {
            operator: "<=".into(),
            kind: PropertyKind::CustomDataNumber {
                key: "abc".into(),
                value: 1.0
            }
        })]
    );
    assert_eq!(
        parse("prop:cds:abc=foo")?,
        vec![Search(Property {
            operator: "=".into(),
            kind: PropertyKind::CustomDataString {
                key: "abc".into(),
                value: "foo".into()
            }
        })]
    );
    assert_eq!(
        parse("\"prop:cds:abc=foo bar\"")?,
        vec![Search(Property {
            operator: "=".into(),
            kind: PropertyKind::CustomDataString {
                key: "abc".into(),
                value: "foo bar".into()
            }
        })]
    );
    assert_eq!(parse("has-cd:r")?, vec![Search(CustomData("r".into()))]);

    Ok(())
}

#[test]
fn errors() {
    use SearchErrorKind::*;

    use crate::error::AnkiError;

    fn assert_err_kind(input: &str, kind: SearchErrorKind) {
        assert_eq!(parse(input), Err(AnkiError::SearchError { source: kind }));
    }

    fn failkind(input: &str) -> SearchErrorKind {
        if let Err(AnkiError::SearchError { source: err }) = parse(input) {
            err
        } else {
            panic!("expected search error");
        }
    }

    assert_err_kind("foo and", MisplacedAnd);
    assert_err_kind("and foo", MisplacedAnd);
    assert_err_kind("and", MisplacedAnd);

    assert_err_kind("foo or", MisplacedOr);
    assert_err_kind("or foo", MisplacedOr);
    assert_err_kind("or", MisplacedOr);

    assert_err_kind("()", EmptyGroup);
    assert_err_kind("( )", EmptyGroup);
    assert_err_kind("(foo () bar)", EmptyGroup);

    assert_err_kind(")", UnopenedGroup);
    assert_err_kind("foo ) bar", UnopenedGroup);
    assert_err_kind("(foo) bar)", UnopenedGroup);

    assert_err_kind("(", UnclosedGroup);
    assert_err_kind("foo ( bar", UnclosedGroup);
    assert_err_kind("(foo (bar)", UnclosedGroup);

    assert_err_kind(r#""""#, EmptyQuote);
    assert_err_kind(r#"foo:"""#, EmptyQuote);

    assert_err_kind(r#" " "#, UnclosedQuote);
    assert_err_kind(r#"" foo"#, UnclosedQuote);
    assert_err_kind(r#""\"#, UnclosedQuote);
    assert_err_kind(r#"foo:"bar"#, UnclosedQuote);
    assert_err_kind(r#"foo:"bar\"#, UnclosedQuote);

    assert_err_kind(":", MissingKey);
    assert_err_kind(":foo", MissingKey);
    assert_err_kind(r#":"foo""#, MissingKey);

    assert_err_kind(
        r"\",
        UnknownEscape {
            provided: r"\".to_string(),
        },
    );
    assert_err_kind(
        r"\%",
        UnknownEscape {
            provided: r"\%".to_string(),
        },
    );
    assert_err_kind(
        r"foo\",
        UnknownEscape {
            provided: r"\".to_string(),
        },
    );
    assert_err_kind(
        r"\foo",
        UnknownEscape {
            provided: r"\f".to_string(),
        },
    );
    assert_err_kind(
        r"\ ",
        UnknownEscape {
            provided: r"\".to_string(),
        },
    );
    assert_err_kind(
        r#""\ ""#,
        UnknownEscape {
            provided: r"\ ".to_string(),
        },
    );

    for term in &[
        "nid:1_2,3",
        "nid:1,2,x",
        "nid:,2,3",
        "nid:1,2,",
        "cid:1_2,3",
        "cid:1,2,x",
        "cid:,2,3",
        "cid:1,2,",
    ] {
        assert!(matches!(failkind(term), SearchErrorKind::Other { .. }));
    }

    assert_err_kind(
        "is:foo",
        InvalidState {
            provided: "foo".into(),
        },
    );
    assert_err_kind(
        "is:DUE",
        InvalidState {
            provided: "DUE".into(),
        },
    );
    assert_err_kind(
        "is:New",
        InvalidState {
            provided: "New".into(),
        },
    );
    assert_err_kind(
        "is:",
        InvalidState {
            provided: "".into(),
        },
    );
    assert_err_kind(
        r#""is:learn ""#,
        InvalidState {
            provided: "learn ".into(),
        },
    );

    assert_err_kind(r#""flag: ""#, InvalidFlag);
    assert_err_kind("flag:-0", InvalidFlag);
    assert_err_kind("flag:", InvalidFlag);
    assert_err_kind("flag:8", InvalidFlag);
    assert_err_kind("flag:1.1", InvalidFlag);

    for term in &["added", "edited", "rated", "resched"] {
        assert!(matches!(
            failkind(&format!("{term}:1.1")),
            SearchErrorKind::InvalidPositiveWholeNumber { .. }
        ));
        assert!(matches!(
            failkind(&format!("{term}:-1")),
            SearchErrorKind::InvalidPositiveWholeNumber { .. }
        ));
        assert!(matches!(
            failkind(&format!("{term}:")),
            SearchErrorKind::InvalidPositiveWholeNumber { .. }
        ));
        assert!(matches!(
            failkind(&format!("{term}:foo")),
            SearchErrorKind::InvalidPositiveWholeNumber { .. }
        ));
    }

    assert!(matches!(
        failkind("rated:1:"),
        SearchErrorKind::InvalidAnswerButton { .. }
    ));
    assert!(matches!(
        failkind("rated:2:-1"),
        SearchErrorKind::InvalidAnswerButton { .. }
    ));
    assert!(matches!(
        failkind("rated:3:1.1"),
        SearchErrorKind::InvalidAnswerButton { .. }
    ));
    assert!(matches!(
        failkind("rated:0:foo"),
        SearchErrorKind::InvalidAnswerButton { .. }
    ));

    assert!(matches!(
        failkind("dupe:"),
        SearchErrorKind::InvalidWholeNumber { .. }
    ));
    assert!(matches!(
        failkind("dupe:1.1"),
        SearchErrorKind::InvalidWholeNumber { .. }
    ));
    assert!(matches!(
        failkind("dupe:foo"),
        SearchErrorKind::InvalidWholeNumber { .. }
    ));

    assert_err_kind(
        "prop:",
        InvalidPropProperty {
            provided: "".into(),
        },
    );
    assert_err_kind(
        "prop:=1",
        InvalidPropProperty {
            provided: "=1".into(),
        },
    );
    assert_err_kind(
        "prop:DUE<5",
        InvalidPropProperty {
            provided: "DUE<5".into(),
        },
    );
    assert_err_kind(
        "prop:cdn=5",
        InvalidPropProperty {
            provided: "cdn=5".to_string(),
        },
    );
    assert_err_kind(
        "prop:cdn:=5",
        InvalidPropProperty {
            provided: "cdn:=5".to_string(),
        },
    );
    assert_err_kind(
        "prop:cds=s",
        InvalidPropProperty {
            provided: "cds=s".to_string(),
        },
    );
    assert_err_kind(
        "prop:cds:=s",
        InvalidPropProperty {
            provided: "cds:=s".to_string(),
        },
    );

    assert_err_kind(
        "prop:lapses",
        InvalidPropOperator {
            provided: "lapses".to_string(),
        },
    );
    assert_err_kind(
        "prop:pos~1",
        InvalidPropOperator {
            provided: "pos".to_string(),
        },
    );
    assert_err_kind(
        "prop:reps10",
        InvalidPropOperator {
            provided: "reps".to_string(),
        },
    );

    // unsigned

    for term in &["ivl", "reps", "lapses", "pos"] {
        assert!(matches!(
            failkind(&format!("prop:{term}>")),
            SearchErrorKind::InvalidPositiveWholeNumber { .. }
        ));
        assert!(matches!(
            failkind(&format!("prop:{term}=0.5")),
            SearchErrorKind::InvalidPositiveWholeNumber { .. }
        ));
        assert!(matches!(
            failkind(&format!("prop:{term}!=-1")),
            SearchErrorKind::InvalidPositiveWholeNumber { .. }
        ));
        assert!(matches!(
            failkind(&format!("prop:{term}<foo")),
            SearchErrorKind::InvalidPositiveWholeNumber { .. }
        ));
    }

    // signed

    assert!(matches!(
        failkind("prop:due>"),
        SearchErrorKind::InvalidWholeNumber { .. }
    ));
    assert!(matches!(
        failkind("prop:due=0.5"),
        SearchErrorKind::InvalidWholeNumber { .. }
    ));

    // float

    assert!(matches!(
        failkind("prop:ease>"),
        SearchErrorKind::InvalidNumber { .. }
    ));
    assert!(matches!(
        failkind("prop:ease!=one"),
        SearchErrorKind::InvalidNumber { .. }
    ));
    assert!(matches!(
        failkind("prop:ease<1,3"),
        SearchErrorKind::InvalidNumber { .. }
    ));
}
