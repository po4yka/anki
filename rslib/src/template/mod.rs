// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

mod field;
mod parser;
mod render;

use std::borrow::Cow;
use std::collections::HashMap;

use anki_i18n::I18n;

use crate::cloze::cloze_number_in_fields;
use crate::error::Result;
use crate::invalid_input;

pub use self::field::FieldMap;
pub use self::field::FieldRequirements;
pub use self::parser::ParsedTemplate;
pub use self::parser::Token;
pub use self::render::RenderContext;
pub use self::render::RenderedNode;
pub use self::render::field_is_empty;

use self::parser::template_error_to_anki_error;
use self::render::nonempty_fields;

// Rendering both sides
//----------------------------------------

#[derive(Clone)]
pub struct RenderCardRequest<'a> {
    pub qfmt: &'a str,
    pub afmt: &'a str,
    pub field_map: &'a HashMap<&'a str, Cow<'a, str>>,
    pub card_ord: u16,
    pub is_cloze: bool,
    pub browser: bool,
    pub tr: &'a I18n,
    pub partial_render: bool,
}

pub struct RenderCardResponse {
    pub qnodes: Vec<RenderedNode>,
    pub anodes: Vec<RenderedNode>,
    pub is_empty: bool,
}

/// Returns `(qnodes, anodes, is_empty)`
pub fn render_card(
    RenderCardRequest {
        qfmt,
        afmt,
        field_map,
        card_ord,
        is_cloze,
        browser,
        tr,
        partial_render: partial_for_python,
    }: RenderCardRequest<'_>,
) -> Result<RenderCardResponse> {
    use self::parser::TEMPLATE_BLANK_CLOZE_LINK;
    use self::parser::TEMPLATE_BLANK_LINK;

    // prepare context
    let mut context = RenderContext {
        fields: field_map,
        nonempty_fields: &nonempty_fields(field_map),
        frontside: None,
        card_ord,
        partial_for_python,
    };

    // question side
    let (mut qnodes, qtmpl) = ParsedTemplate::from_text(qfmt)
        .and_then(|tmpl| Ok((tmpl.render(&context, tr)?, tmpl)))
        .map_err(|e| template_error_to_anki_error(e, true, browser, tr))?;

    // check if the front side was empty
    let empty_message = if is_cloze && cloze_is_empty(field_map, card_ord) {
        Some(format!(
            "<div>{}<br><a href='{}'>{}</a></div>",
            tr.card_template_rendering_missing_cloze(card_ord + 1),
            TEMPLATE_BLANK_CLOZE_LINK,
            tr.card_template_rendering_more_info()
        ))
    } else if !is_cloze && !browser && !qtmpl.renders_with_fields(context.nonempty_fields) {
        Some(format!(
            "<div>{}<br><a href='{}'>{}</a></div>",
            tr.card_template_rendering_empty_front(),
            TEMPLATE_BLANK_LINK,
            tr.card_template_rendering_more_info()
        ))
    } else {
        None
    };
    if let Some(text) = empty_message {
        qnodes.push(RenderedNode::Text { text: text.clone() });
        return Ok(RenderCardResponse {
            qnodes,
            anodes: vec![RenderedNode::Text { text }],
            is_empty: true,
        });
    }

    // answer side
    context.frontside = if context.partial_for_python {
        Some("")
    } else {
        let Some(RenderedNode::Text { text }) = &qnodes.first() else {
            invalid_input!("should not happen: first node not text");
        };
        Some(text)
    };
    let anodes = ParsedTemplate::from_text(afmt)
        .and_then(|tmpl| tmpl.render(&context, tr))
        .map_err(|e| template_error_to_anki_error(e, false, browser, tr))?;

    Ok(RenderCardResponse {
        qnodes,
        anodes,
        is_empty: false,
    })
}

fn cloze_is_empty(field_map: &HashMap<&str, Cow<str>>, card_ord: u16) -> bool {
    !cloze_number_in_fields(field_map.values()).contains(&(card_ord + 1))
}

// Tests
//---------------------------------------

#[cfg(test)]
mod tests;
