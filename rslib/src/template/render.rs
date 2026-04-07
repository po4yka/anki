// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

use std::borrow::Cow;
use std::collections::HashMap;
use std::collections::HashSet;
use std::sync::LazyLock;

use anki_i18n::I18n;
use regex::Regex;

use crate::template_filters::apply_filters;

use super::parser::COMMENT_END;
use super::parser::COMMENT_START;
use super::parser::ParsedNode;
use super::parser::ParsedTemplate;
use super::parser::TemplateResult;

#[derive(Debug, PartialEq, Eq)]
pub enum RenderedNode {
    Text {
        text: String,
    },
    Replacement {
        field_name: String,
        current_text: String,
        /// Filters are in the order they should be applied.
        filters: Vec<String>,
    },
}

pub struct RenderContext<'a> {
    pub fields: &'a HashMap<&'a str, Cow<'a, str>>,
    pub nonempty_fields: &'a HashSet<&'a str>,
    pub card_ord: u16,
    /// Should be set before rendering the answer, even if `partial_for_python`
    /// is true.
    pub frontside: Option<&'a str>,
    /// If true, question/answer will not be fully rendered if an unknown filter
    /// is encountered, and the frontend code will need to complete the
    /// rendering.
    pub partial_for_python: bool,
}

impl ParsedTemplate {
    /// Render the template with the provided fields.
    ///
    /// Replacements that use only standard filters will become part of
    /// a text node. If a non-standard filter is encountered, a partially
    /// rendered Replacement is returned for the calling code to complete.
    pub(super) fn render(
        &self,
        context: &RenderContext,
        _tr: &I18n,
    ) -> TemplateResult<Vec<RenderedNode>> {
        let mut rendered = vec![];

        render_into(&mut rendered, self.0.as_ref(), context)?;

        Ok(rendered)
    }
}

pub(super) fn render_into(
    rendered_nodes: &mut Vec<RenderedNode>,
    nodes: &[ParsedNode],
    context: &RenderContext,
) -> TemplateResult<()> {
    use std::iter;

    use ParsedNode::*;
    for node in nodes {
        match node {
            Text(text) => {
                append_str_to_nodes(rendered_nodes, text);
            }
            Comment(comment) => {
                append_str_to_nodes(rendered_nodes, COMMENT_START);
                append_str_to_nodes(rendered_nodes, comment);
                append_str_to_nodes(rendered_nodes, COMMENT_END);
            }
            Replacement { key, .. } if key == "FrontSide" => {
                let frontside = context.frontside.as_ref().copied().unwrap_or_default();
                if context.partial_for_python {
                    // defer FrontSide rendering to Python, as extra
                    // filters may be required
                    rendered_nodes.push(RenderedNode::Replacement {
                        field_name: (*key).to_string(),
                        filters: vec![],
                        current_text: "".into(),
                    });
                } else {
                    append_str_to_nodes(rendered_nodes, frontside);
                }
            }
            Replacement { key, filters } => {
                if key.is_empty() && !filters.is_empty() {
                    if context.partial_for_python {
                        // if a filter is provided, we accept an empty field name to
                        // mean 'pass an empty string to the filter, and it will add
                        // its own text'
                        rendered_nodes.push(RenderedNode::Replacement {
                            field_name: "".to_string(),
                            current_text: "".to_string(),
                            filters: filters.clone(),
                        });
                    } else {
                        // nothing to do
                    }
                } else {
                    // apply built in filters if field exists
                    let (text, remaining_filters) = match context.fields.get(key.as_str()) {
                        Some(text) => apply_filters(
                            text,
                            filters
                                .iter()
                                .map(|s| s.as_str())
                                .collect::<Vec<_>>()
                                .as_slice(),
                            key,
                            context,
                        ),
                        None => {
                            // unknown field encountered
                            let filters_str = filters
                                .iter()
                                .rev()
                                .cloned()
                                .chain(iter::once("".into()))
                                .collect::<Vec<_>>()
                                .join(":");
                            return Err(crate::error::TemplateError::FieldNotFound {
                                field: (*key).to_string(),
                                filters: filters_str,
                            });
                        }
                    };

                    // fully processed?
                    if remaining_filters.is_empty() {
                        append_str_to_nodes(rendered_nodes, text.as_ref())
                    } else {
                        rendered_nodes.push(RenderedNode::Replacement {
                            field_name: (*key).to_string(),
                            filters: remaining_filters,
                            current_text: text.into(),
                        });
                    }
                }
            }
            Conditional { key, children } => {
                if context.evaluate_conditional(key.as_str(), false)? {
                    render_into(rendered_nodes, children.as_ref(), context)?;
                } else {
                    // keep checking for errors, but discard rendered nodes
                    render_into(&mut vec![], children.as_ref(), context)?;
                }
            }
            NegatedConditional { key, children } => {
                if context.evaluate_conditional(key.as_str(), true)? {
                    render_into(rendered_nodes, children.as_ref(), context)?;
                } else {
                    render_into(&mut vec![], children.as_ref(), context)?;
                }
            }
        };
    }

    Ok(())
}

impl RenderContext<'_> {
    pub(super) fn evaluate_conditional(&self, key: &str, negated: bool) -> TemplateResult<bool> {
        if self.nonempty_fields.contains(key) {
            Ok(true ^ negated)
        } else if self.fields.contains_key(key) || super::field::is_cloze_conditional(key) {
            Ok(false ^ negated)
        } else {
            let prefix = if negated { "^" } else { "#" };
            Err(crate::error::TemplateError::NoSuchConditional(format!(
                "{prefix}{key}"
            )))
        }
    }
}

/// Append to last node if last node is a string, else add new node.
pub(super) fn append_str_to_nodes(nodes: &mut Vec<RenderedNode>, text: &str) {
    if let Some(RenderedNode::Text {
        text: existing_text,
    }) = nodes.last_mut()
    {
        // append to existing last node
        existing_text.push_str(text)
    } else {
        // otherwise, add a new string node
        nodes.push(RenderedNode::Text {
            text: text.to_string(),
        })
    }
}

/// True if provided text contains only whitespace and/or empty BR/DIV tags.
pub fn field_is_empty(text: &str) -> bool {
    static RE: LazyLock<Regex> = LazyLock::new(|| {
        Regex::new(
            r"(?xsi)
            ^(?:
            [[:space:]]
            |
            </?(?:br|div)\ ?/?>
            )*$
        ",
        )
        .unwrap()
    });
    RE.is_match(text)
}

pub(super) fn nonempty_fields<'a, R>(fields: &'a HashMap<&str, R>) -> HashSet<&'a str>
where
    R: AsRef<str>,
{
    fields
        .iter()
        .filter_map(|(name, val)| {
            if !field_is_empty(val.as_ref()) {
                Some(*name)
            } else {
                None
            }
        })
        .collect()
}
