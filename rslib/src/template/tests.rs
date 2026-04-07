// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

use std::collections::HashMap;

use anki_i18n::I18n;

use super::FieldMap;
use super::FieldRequirements;
use super::ParsedTemplate as PT;
use super::RenderCardRequest;
use super::RenderContext;
use super::field_is_empty;
use super::parser::COMMENT_END;
use super::parser::COMMENT_START;
use super::parser::ParsedNode::*;
use super::render::nonempty_fields;
use crate::error::TemplateError;

#[test]
fn field_empty() {
    assert!(field_is_empty(""));
    assert!(field_is_empty(" "));
    assert!(!field_is_empty("x"));
    assert!(field_is_empty("<BR>"));
    assert!(field_is_empty("<div />"));
    assert!(field_is_empty(" <div> <br> </div>\n"));
    assert!(!field_is_empty(" <div>x</div>\n"));
}

#[test]
fn parsing() {
    let orig = "";
    let tmpl = PT::from_text(orig).unwrap();
    assert_eq!(tmpl.0, vec![]);
    assert_eq!(orig, &tmpl.template_to_string());

    let orig = "foo {{bar}} {{#baz}} quux {{/baz}}";
    let tmpl = PT::from_text(orig).unwrap();
    assert_eq!(
        tmpl.0,
        vec![
            Text("foo ".into()),
            Replacement {
                key: "bar".into(),
                filters: vec![]
            },
            Text(" ".into()),
            Conditional {
                key: "baz".into(),
                children: vec![Text(" quux ".into())]
            }
        ]
    );
    assert_eq!(orig, &tmpl.template_to_string());

    // Hardcode comment delimiters into tests to keep them concise
    assert_eq!(COMMENT_START, "<!--");
    assert_eq!(COMMENT_END, "-->");

    let orig = "foo <!--{{bar }} --> {{#baz}} --> <!-- <!-- {{#def}} --> \u{123}-->\u{456}<!-- 2 --><!----> <!-- quux {{/baz}} <!-- {{nc:abc}}";
    let tmpl = PT::from_text(orig).unwrap();
    assert_eq!(
        tmpl.0,
        vec![
            Text("foo ".into()),
            Comment("{{bar }} ".into()),
            Text(" ".into()),
            Conditional {
                key: "baz".into(),
                children: vec![
                    Text(" --> ".into()),
                    Comment(" <!-- {{#def}} ".into()),
                    Text(" \u{123}-->\u{456}".into()),
                    Comment(" 2 ".into()),
                    Comment("".into()),
                    Text(" <!-- quux ".into()),
                ]
            },
            Text(" <!-- ".into()),
            Replacement {
                key: "abc".into(),
                filters: vec!["nc".into()]
            }
        ]
    );
    assert_eq!(orig, &tmpl.template_to_string());

    let tmpl = PT::from_text("{{^baz}}{{/baz}}").unwrap();
    assert_eq!(
        tmpl.0,
        vec![NegatedConditional {
            key: "baz".into(),
            children: vec![]
        }]
    );

    PT::from_text("{{#mis}}{{/matched}}").unwrap_err();
    PT::from_text("{{/matched}}").unwrap_err();
    PT::from_text("{{#mis}}").unwrap_err();
    PT::from_text("{{#mis}}<!--{{/matched}}-->").unwrap_err();
    PT::from_text("<!--{{#mis}}{{/matched}}-->").unwrap();
    PT::from_text("<!--{{foo}}").unwrap();
    PT::from_text("{{foo}}-->").unwrap();

    // whitespace
    assert_eq!(
        PT::from_text("{{ tag }}").unwrap().0,
        vec![Replacement {
            key: "tag".into(),
            filters: vec![]
        }]
    );

    // stray closing characters (like in javascript) are ignored
    assert_eq!(
        PT::from_text("text }} more").unwrap().0,
        vec![Text("text }} more".into())]
    );

    // make sure filters and so on are round-tripped correctly
    let orig = "foo {{one:two}} {{one:two:three}} {{^baz}} {{/baz}} {{foo:}}";
    let tmpl = PT::from_text(orig).unwrap();
    assert_eq!(orig, &tmpl.template_to_string());

    let orig = "foo {{one:two}} <!--<!--abc {{^def}}-->--> {{one:two:three}} {{^baz}} <!-- {{/baz}} 🙂 --> {{/baz}} {{foo:}}";
    let tmpl = PT::from_text(orig).unwrap();
    assert_eq!(orig, &tmpl.template_to_string());
}

#[test]
fn nonempty() {
    let fields = vec!["1", "3"].into_iter().collect();
    let mut tmpl = PT::from_text("{{2}}{{1}}").unwrap();
    assert!(tmpl.renders_with_fields(&fields));
    tmpl = PT::from_text("{{2}}").unwrap();
    assert!(!tmpl.renders_with_fields(&fields));
    tmpl = PT::from_text("{{2}}{{4}}").unwrap();
    assert!(!tmpl.renders_with_fields(&fields));
    tmpl = PT::from_text("{{#3}}{{^2}}{{1}}{{/2}}{{/3}}").unwrap();
    assert!(tmpl.renders_with_fields(&fields));

    tmpl = PT::from_text("{{^1}}{{3}}{{/1}}").unwrap();
    assert!(!tmpl.renders_with_fields(&fields));
    assert!(tmpl.renders_with_fields_for_reqs(&fields));
}

#[test]
fn requirements() {
    let field_map: FieldMap = ["a", "b", "c"]
        .iter()
        .enumerate()
        .map(|(a, b)| (*b, a as u16))
        .collect();

    let mut tmpl = PT::from_text("{{a}}{{b}}").unwrap();
    assert_eq!(
        tmpl.requirements(&field_map),
        FieldRequirements::Any(vec![0, 1].into_iter().collect())
    );

    tmpl = PT::from_text("{{#a}}{{b}}{{/a}}").unwrap();
    assert_eq!(
        tmpl.requirements(&field_map),
        FieldRequirements::All(vec![0, 1].into_iter().collect())
    );

    tmpl = PT::from_text("{{z}}").unwrap();
    assert_eq!(tmpl.requirements(&field_map), FieldRequirements::None);

    tmpl = PT::from_text("{{^a}}{{b}}{{/a}}").unwrap();
    assert_eq!(
        tmpl.requirements(&field_map),
        FieldRequirements::Any(vec![1].into_iter().collect())
    );

    tmpl = PT::from_text("{{^a}}{{#b}}{{c}}{{/b}}{{/a}}").unwrap();
    assert_eq!(
        tmpl.requirements(&field_map),
        FieldRequirements::All(vec![1, 2].into_iter().collect())
    );

    tmpl = PT::from_text("{{#a}}{{#b}}{{a}}{{/b}}{{/a}}").unwrap();
    assert_eq!(
        tmpl.requirements(&field_map),
        FieldRequirements::All(vec![0, 1].into_iter().collect())
    );

    tmpl = PT::from_text(
        r#"
{{^a}}
    {{b}}
{{/a}}

{{#a}}
    {{a}}
    {{b}}
{{/a}}
"#,
    )
    .unwrap();

    // Hardcode comment delimiters into tests to keep them concise
    assert_eq!(COMMENT_START, "<!--");
    assert_eq!(COMMENT_END, "-->");

    assert_eq!(
        tmpl.requirements(&field_map),
        FieldRequirements::Any(vec![0, 1].into_iter().collect())
    );

    tmpl = PT::from_text(
        r#"
<!--{{^a}}-->
    {{b}}
<!--{{/a}}-->
{{#c}}
    <!--{{a}}-->
    {{b}}
    <!--{{c}}-->
{{/c}}
"#,
    )
    .unwrap();

    assert_eq!(
        tmpl.requirements(&field_map),
        FieldRequirements::Any(vec![1].into_iter().collect())
    );
}

#[test]
fn alt_syntax() {
    let input = "
{{=<% %>=}}
<%Front%>
<% #Back %>
<%/Back%>";
    assert_eq!(
        PT::from_text(input).unwrap().0,
        vec![
            Text("\n".into()),
            Replacement {
                key: "Front".into(),
                filters: vec![]
            },
            Text("\n".into()),
            Conditional {
                key: "Back".into(),
                children: vec![Text("\n".into())]
            }
        ]
    );
    let input = "
{{=<% %>=}}
{{#foo}}
<%Front%>
{{/foo}}
";
    assert_eq!(
        PT::from_text(input).unwrap().0,
        vec![
            Text("\n{{#foo}}\n".into()),
            Replacement {
                key: "Front".into(),
                filters: vec![]
            },
            Text("\n{{/foo}}\n".into())
        ]
    );
}

#[test]
fn render_single() {
    let map: HashMap<_, _> = vec![("F", "f"), ("B", "b"), ("E", " "), ("c1", "1")]
        .into_iter()
        .map(|r| (r.0, r.1.into()))
        .collect();

    let ctx = RenderContext {
        fields: &map,
        nonempty_fields: &nonempty_fields(&map),
        frontside: None,
        card_ord: 1,
        partial_for_python: true,
    };

    use super::RenderedNode as FN;
    let mut tmpl = PT::from_text("{{B}}A{{F}}").unwrap();
    let tr = I18n::template_only();
    assert_eq!(
        tmpl.render(&ctx, &tr).unwrap(),
        vec![FN::Text {
            text: "bAf".to_owned()
        },]
    );

    // empty
    tmpl = PT::from_text("{{#E}}A{{/E}}").unwrap();
    assert_eq!(tmpl.render(&ctx, &tr).unwrap(), vec![]);

    // missing
    tmpl = PT::from_text("{{#E}}}{{^M}}A{{/M}}{{/E}}}").unwrap();
    assert_eq!(
        tmpl.render(&ctx, &tr).unwrap_err(),
        TemplateError::NoSuchConditional("^M".to_string())
    );

    // nested
    tmpl = PT::from_text("{{^E}}1{{#F}}2{{#B}}{{F}}{{/B}}{{/F}}{{/E}}").unwrap();
    assert_eq!(
        tmpl.render(&ctx, &tr).unwrap(),
        vec![FN::Text {
            text: "12f".to_owned()
        },]
    );

    // Hardcode comment delimiters into tests to keep them concise
    assert_eq!(COMMENT_START, "<!--");
    assert_eq!(COMMENT_END, "-->");

    // commented
    tmpl = PT::from_text(
        "{{^E}}1<!--{{#F}}2{{#B}}{{F}}{{/B}}{{/F}}-->\u{123}<!-- this is a comment -->{{/E}}\u{456}",
    )
    .unwrap();
    assert_eq!(
        tmpl.render(&ctx, &tr).unwrap(),
        vec![FN::Text {
            text: "1<!--{{#F}}2{{#B}}{{F}}{{/B}}{{/F}}-->\u{123}<!-- this is a comment -->\u{456}"
                .to_owned()
        },]
    );

    // card conditionals
    tmpl = PT::from_text("{{^c2}}1{{#c1}}2{{/c1}}{{/c2}}").unwrap();
    assert_eq!(
        tmpl.render(&ctx, &tr).unwrap(),
        vec![FN::Text {
            text: "12".to_owned()
        },]
    );

    // unknown filters
    tmpl = PT::from_text("{{one:two:B}}").unwrap();
    assert_eq!(
        tmpl.render(&ctx, &tr).unwrap(),
        vec![FN::Replacement {
            field_name: "B".to_owned(),
            filters: vec!["two".to_string(), "one".to_string()],
            current_text: "b".to_owned()
        },]
    );

    // partially unknown filters
    // excess colons are ignored
    tmpl = PT::from_text("{{one::text:B}}").unwrap();
    assert_eq!(
        tmpl.render(&ctx, &tr).unwrap(),
        vec![FN::Replacement {
            field_name: "B".to_owned(),
            filters: vec!["one".to_string()],
            current_text: "b".to_owned()
        },]
    );

    // known filter
    tmpl = PT::from_text("{{text:B}}").unwrap();
    assert_eq!(
        tmpl.render(&ctx, &tr).unwrap(),
        vec![FN::Text {
            text: "b".to_owned()
        }]
    );

    // unknown field
    tmpl = PT::from_text("{{X}}").unwrap();
    assert_eq!(
        tmpl.render(&ctx, &tr).unwrap_err(),
        TemplateError::FieldNotFound {
            field: "X".to_owned(),
            filters: "".to_owned()
        }
    );

    // unknown field with filters
    tmpl = PT::from_text("{{foo:text:X}}").unwrap();
    assert_eq!(
        tmpl.render(&ctx, &tr).unwrap_err(),
        TemplateError::FieldNotFound {
            field: "X".to_owned(),
            filters: "foo:text:".to_owned()
        }
    );

    // a blank field is allowed if it has filters
    tmpl = PT::from_text("{{filter:}}").unwrap();
    assert_eq!(
        tmpl.render(&ctx, &tr).unwrap(),
        vec![FN::Replacement {
            field_name: "".to_string(),
            current_text: "".to_string(),
            filters: vec!["filter".to_string()]
        }]
    );
}

#[test]
fn render_card() {
    let map: HashMap<_, _> = vec![("E", ""), ("N", "N")]
        .into_iter()
        .map(|r| (r.0, r.1.into()))
        .collect();

    let tr = I18n::template_only();
    use super::RenderedNode as FN;

    let mut req = RenderCardRequest {
        qfmt: "test{{E}}",
        afmt: "",
        field_map: &map,
        card_ord: 1,
        is_cloze: false,
        browser: false,
        tr: &tr,
        partial_render: true,
    };
    let response = super::render_card(req.clone()).unwrap();
    assert_eq!(
        response.qnodes[0],
        FN::Text {
            text: "test".into()
        }
    );
    assert!(response.is_empty);
    if let FN::Text { ref text } = response.qnodes[1] {
        assert!(text.contains("card is blank"));
    } else {
        unreachable!();
    }

    // a popular card template expects {{FrontSide}} to resolve to an empty
    // string on the front side :-(
    req.qfmt = "{{FrontSide}}{{N}}";
    let response = super::render_card(req.clone()).unwrap();
    assert_eq!(
        &response.qnodes,
        &[
            FN::Replacement {
                field_name: "FrontSide".into(),
                current_text: "".into(),
                filters: vec![]
            },
            FN::Text { text: "N".into() }
        ]
    );
    assert!(!response.is_empty);
    req.partial_render = false;
    let response = super::render_card(req.clone()).unwrap();
    assert_eq!(&response.qnodes, &[FN::Text { text: "N".into() }]);
    assert!(!response.is_empty);
}
