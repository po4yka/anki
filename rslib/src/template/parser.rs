// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

use std::iter;

use anki_i18n::I18n;
use nom::Parser;
use nom::bytes::complete::tag;
use nom::bytes::complete::take_until;
use nom::combinator::map;
use nom::sequence::delimited;

use crate::error::AnkiError;
use crate::error::TemplateError;

pub(super) type TemplateResult<T> = std::result::Result<T, TemplateError>;

pub(super) static TEMPLATE_ERROR_LINK: &str =
    "https://docs.ankiweb.net/templates/errors.html#template-syntax-error";
pub(super) static TEMPLATE_BLANK_LINK: &str =
    "https://docs.ankiweb.net/templates/errors.html#front-of-card-is-blank";
pub(super) static TEMPLATE_BLANK_CLOZE_LINK: &str =
    "https://docs.ankiweb.net/templates/errors.html#no-cloze-filter-on-cloze-note-type";

// Template comment delimiters
pub(super) static COMMENT_START: &str = "<!--";
pub(super) static COMMENT_END: &str = "-->";

static ALT_HANDLEBAR_DIRECTIVE: &str = "{{=<% %>=}}";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum TemplateMode {
    Standard,
    LegacyAltSyntax,
}

impl TemplateMode {
    fn start_tag(&self) -> &'static str {
        match self {
            TemplateMode::Standard => "{{",
            TemplateMode::LegacyAltSyntax => "<%",
        }
    }

    fn end_tag(&self) -> &'static str {
        match self {
            TemplateMode::Standard => "}}",
            TemplateMode::LegacyAltSyntax => "%>",
        }
    }

    fn handlebar_token<'b>(&self, s: &'b str) -> nom::IResult<&'b str, Token<'b>> {
        map(
            delimited(
                tag(self.start_tag()),
                take_until(self.end_tag()),
                tag(self.end_tag()),
            ),
            |out| classify_handle(out),
        )
        .parse(s)
    }

    /// Return the next handlebar, comment or text token.
    fn next_token<'b>(&self, input: &'b str) -> Option<(&'b str, Token<'b>)> {
        if input.is_empty() {
            return None;
        }

        // Loop, starting from the first character
        for (i, _) in input.char_indices() {
            let remaining = &input[i..];

            // Valid handlebar clause?
            if let Ok((after_handlebar, token)) = self.handlebar_token(remaining) {
                // Found at the start of string, so that's the next token
                return Some(if i == 0 {
                    (after_handlebar, token)
                } else {
                    // There was some text prior to this, so return it instead
                    (remaining, Token::Text(&input[..i]))
                });
            }

            // Check comments too
            if let Ok((after_comment, token)) = comment_token(remaining) {
                return Some(if i == 0 {
                    (after_comment, token)
                } else {
                    (remaining, Token::Text(&input[..i]))
                });
            }
        }

        // If no matches, return the entire input as text, with nothing remaining
        Some(("", Token::Text(input)))
    }
}

// Lexing
//----------------------------------------

#[derive(Debug)]
pub enum Token<'a> {
    Text(&'a str),
    Comment(&'a str),
    Replacement(&'a str),
    OpenConditional(&'a str),
    OpenNegated(&'a str),
    CloseConditional(&'a str),
}

fn comment_token(s: &str) -> nom::IResult<&str, Token<'_>> {
    map(
        delimited(
            tag(COMMENT_START),
            take_until(COMMENT_END),
            tag(COMMENT_END),
        ),
        Token::Comment,
    )
    .parse(s)
}

pub(super) fn tokens(mut template: &str) -> impl Iterator<Item = TemplateResult<Token<'_>>> {
    let mode = if template.trim_start().starts_with(ALT_HANDLEBAR_DIRECTIVE) {
        template = template
            .trim_start()
            .trim_start_matches(ALT_HANDLEBAR_DIRECTIVE);

        TemplateMode::LegacyAltSyntax
    } else {
        TemplateMode::Standard
    };
    iter::from_fn(move || {
        let token;
        (template, token) = mode.next_token(template)?;
        Some(Ok(token))
    })
}

/// classify handle based on leading character
fn classify_handle(s: &str) -> Token<'_> {
    let start = s.trim_start_matches('{').trim();
    if start.len() < 2 {
        return Token::Replacement(start);
    }
    if let Some(stripped) = start.strip_prefix('#') {
        Token::OpenConditional(stripped.trim_start())
    } else if let Some(stripped) = start.strip_prefix('/') {
        Token::CloseConditional(stripped.trim_start())
    } else if let Some(stripped) = start.strip_prefix('^') {
        Token::OpenNegated(stripped.trim_start())
    } else {
        Token::Replacement(start)
    }
}

// Parsing
//----------------------------------------

#[derive(Debug, PartialEq, Eq)]
pub(super) enum ParsedNode {
    Text(String),
    Comment(String),
    Replacement {
        key: String,
        filters: Vec<String>,
    },
    Conditional {
        key: String,
        children: Vec<ParsedNode>,
    },
    NegatedConditional {
        key: String,
        children: Vec<ParsedNode>,
    },
}

#[derive(Debug)]
pub struct ParsedTemplate(pub(super) Vec<ParsedNode>);

impl ParsedTemplate {
    /// Create a template from the provided text.
    pub fn from_text(template: &str) -> TemplateResult<ParsedTemplate> {
        let mut iter = tokens(template);
        Ok(Self(parse_inner(&mut iter, None)?))
    }
}

pub(super) fn parse_inner<'a, I: Iterator<Item = TemplateResult<Token<'a>>>>(
    iter: &mut I,
    open_tag: Option<&'a str>,
) -> TemplateResult<Vec<ParsedNode>> {
    let mut nodes = vec![];

    while let Some(token) = iter.next() {
        use Token::*;
        nodes.push(match token? {
            Text(t) => ParsedNode::Text(t.into()),
            Comment(t) => ParsedNode::Comment(t.into()),
            Replacement(t) => {
                let mut it = t.rsplit(':');
                ParsedNode::Replacement {
                    key: it.next().unwrap().into(),
                    filters: it.map(Into::into).collect(),
                }
            }
            OpenConditional(t) => ParsedNode::Conditional {
                key: t.into(),
                children: parse_inner(iter, Some(t))?,
            },
            OpenNegated(t) => ParsedNode::NegatedConditional {
                key: t.into(),
                children: parse_inner(iter, Some(t))?,
            },
            CloseConditional(t) => {
                let currently_open = if let Some(open) = open_tag {
                    if open == t {
                        // matching closing tag, move back to parent
                        return Ok(nodes);
                    } else {
                        Some(open.to_string())
                    }
                } else {
                    None
                };
                return Err(TemplateError::ConditionalNotOpen {
                    closed: t.to_string(),
                    currently_open,
                });
            }
        });
    }

    if let Some(open) = open_tag {
        Err(TemplateError::ConditionalNotClosed(open.to_string()))
    } else {
        Ok(nodes)
    }
}

pub(super) fn template_error_to_anki_error(
    err: TemplateError,
    q_side: bool,
    browser: bool,
    tr: &I18n,
) -> AnkiError {
    let header = match (q_side, browser) {
        (true, false) => tr.card_template_rendering_front_side_problem(),
        (false, false) => tr.card_template_rendering_back_side_problem(),
        (true, true) => tr.card_template_rendering_browser_front_side_problem(),
        (false, true) => tr.card_template_rendering_browser_back_side_problem(),
    };
    let details = htmlescape::encode_minimal(&localized_template_error(tr, err));
    let more_info = tr.card_template_rendering_more_info();
    let source =
        format!("{header}<br>{details}<br><a href='{TEMPLATE_ERROR_LINK}'>{more_info}</a>");

    AnkiError::TemplateError { info: source }
}

fn localized_template_error(tr: &I18n, err: TemplateError) -> String {
    match err {
        TemplateError::NoClosingBrackets(tag) => tr
            .card_template_rendering_no_closing_brackets("}}", tag)
            .into(),
        TemplateError::ConditionalNotClosed(tag) => tr
            .card_template_rendering_conditional_not_closed(format!("{{{{/{tag}}}}}"))
            .into(),
        TemplateError::ConditionalNotOpen {
            closed,
            currently_open,
        } => if let Some(open) = currently_open {
            tr.card_template_rendering_wrong_conditional_closed(
                format!("{{{{/{closed}}}}}"),
                format!("{{{{/{open}}}}}"),
            )
        } else {
            tr.card_template_rendering_conditional_not_open(
                format!("{{{{/{closed}}}}}"),
                format!("{{{{#{closed}}}}}"),
                format!("{{{{^{closed}}}}}"),
            )
        }
        .into(),
        TemplateError::FieldNotFound { field, filters } => tr
            .card_template_rendering_no_such_field(format!("{{{{{filters}{field}}}}}"), field)
            .into(),
        TemplateError::NoSuchConditional(condition) => tr
            .card_template_rendering_no_such_field(format!("{{{{{condition}}}}}"), &condition[1..])
            .into(),
    }
}
