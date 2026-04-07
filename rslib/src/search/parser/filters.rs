// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

use std::sync::LazyLock;

use nom::Parser;
use nom::branch::alt;
use nom::bytes::complete::is_not;
use nom::bytes::complete::tag;
use nom::character::complete::alphanumeric1;
use nom::character::complete::anychar;
use nom::combinator::recognize;
use nom::sequence::preceded;
use regex::Captures;
use regex::Regex;

use super::ParseResult;
use super::ast::FieldSearchMode;
use super::ast::PropertyKind;
use super::ast::RatingKind;
use super::ast::SearchNode;
use super::ast::StateKind;
use super::ast::TemplateKind;
use super::error::parse_failure;
use crate::error::ParseError;
use crate::error::SearchErrorKind as FailKind;

/// Determine if text is a qualified search, and handle escaped chars.
/// Expect well-formed input: unempty and no trailing \.
pub(super) fn search_node_for_text(s: &str) -> ParseResult<'_, SearchNode> {
    // leading : is only possible error for well-formed input
    let (tail, head) = nom::combinator::verify(
        nom::bytes::complete::escaped(is_not(r":\"), '\\', anychar),
        |t: &str| !t.is_empty(),
    )
    .parse(s)
    .map_err(|_: nom::Err<ParseError>| parse_failure(s, FailKind::MissingKey))?;
    if tail.is_empty() {
        Ok(SearchNode::UnqualifiedText(unescape(head)?))
    } else {
        search_node_for_text_with_argument(head, &tail[1..])
    }
}

/// Convert a colon-separated key/val pair into the relevant search type.
pub(super) fn search_node_for_text_with_argument<'a>(
    key: &'a str,
    val: &'a str,
) -> ParseResult<'a, SearchNode> {
    Ok(match key.to_ascii_lowercase().as_str() {
        "deck" => SearchNode::Deck(unescape(val)?),
        "note" => SearchNode::Notetype(unescape(val)?),
        "tag" => parse_tag(val)?,
        "card" => parse_template(val)?,
        "flag" => parse_flag(val)?,
        "resched" => parse_resched(val)?,
        "prop" => parse_prop(val)?,
        "added" => parse_added(val)?,
        "edited" => parse_edited(val)?,
        "introduced" => parse_introduced(val)?,
        "rated" => parse_rated(val)?,
        "is" => parse_state(val)?,
        "did" => SearchNode::DeckIdsWithoutChildren(check_id_list(val, key)?.into()),
        "mid" => parse_mid(val)?,
        "nid" => SearchNode::NoteIds(check_id_list(val, key)?.into()),
        "cid" => SearchNode::CardIds(check_id_list(val, key)?.into()),
        "re" => SearchNode::Regex(unescape_quotes(val)),
        "nc" => SearchNode::NoCombining(unescape(val)?),
        "sc" => SearchNode::StripClozes(unescape(val)?),
        "w" => SearchNode::WordBoundary(unescape(val)?),
        "dupe" => parse_dupe(val)?,
        "has-cd" => SearchNode::CustomData(unescape(val)?),
        "preset" => SearchNode::Preset(val.into()),
        // anything else is a field search
        _ => parse_single_field(key, val)?,
    })
}

fn parse_tag(s: &str) -> ParseResult<'_, SearchNode> {
    Ok(if let Some(re) = s.strip_prefix("re:") {
        SearchNode::Tag {
            tag: unescape_quotes(re),
            mode: FieldSearchMode::Regex,
        }
    } else if let Some(nc) = s.strip_prefix("nc:") {
        SearchNode::Tag {
            tag: unescape(nc)?,
            mode: FieldSearchMode::NoCombining,
        }
    } else {
        SearchNode::Tag {
            tag: unescape(s)?,
            mode: FieldSearchMode::Normal,
        }
    })
}

fn parse_template(s: &str) -> ParseResult<'_, SearchNode> {
    Ok(SearchNode::CardTemplate(match s.parse::<u16>() {
        Ok(n) => TemplateKind::Ordinal(n.max(1) - 1),
        Err(_) => TemplateKind::Name(unescape(s)?),
    }))
}

/// flag:0-7
fn parse_flag(s: &str) -> ParseResult<'_, SearchNode> {
    if let Ok(flag) = s.parse::<u8>() {
        if flag > 7 {
            Err(parse_failure(s, FailKind::InvalidFlag))
        } else {
            Ok(SearchNode::Flag(flag))
        }
    } else {
        Err(parse_failure(s, FailKind::InvalidFlag))
    }
}

/// eg resched:3
fn parse_resched(s: &str) -> ParseResult<'_, SearchNode> {
    parse_u32(s, "resched:").map(|days| SearchNode::Rated {
        days,
        ease: RatingKind::ManualReschedule,
    })
}

/// eg prop:ivl>3, prop:ease!=2.5
fn parse_prop(prop_clause: &str) -> ParseResult<'_, SearchNode> {
    let (tail, prop) = alt((
        tag("ivl"),
        tag("due"),
        tag("reps"),
        tag("lapses"),
        tag("ease"),
        tag("pos"),
        tag("rated"),
        tag("resched"),
        tag("s"),
        tag("d"),
        tag("r"),
        recognize(preceded(tag("cdn:"), alphanumeric1)),
        recognize(preceded(tag("cds:"), alphanumeric1)),
    ))
    .parse(prop_clause)
    .map_err(|_: nom::Err<ParseError>| {
        parse_failure(
            prop_clause,
            FailKind::InvalidPropProperty {
                provided: prop_clause.into(),
            },
        )
    })?;

    let (num, operator) = alt((
        tag("<="),
        tag(">="),
        tag("!="),
        tag("="),
        tag("<"),
        tag(">"),
    ))
    .parse(tail)
    .map_err(|_: nom::Err<ParseError>| {
        parse_failure(
            prop_clause,
            FailKind::InvalidPropOperator {
                provided: prop.to_owned(),
            },
        )
    })?;

    let kind = match prop {
        "ease" => PropertyKind::Ease(parse_f32(num, prop_clause)?),
        "due" => PropertyKind::Due(parse_i32(num, prop_clause)?),
        "rated" => parse_prop_rated(num, prop_clause)?,
        "resched" => PropertyKind::Rated(
            parse_negative_i32(num, prop_clause)?,
            RatingKind::ManualReschedule,
        ),
        "ivl" => PropertyKind::Interval(parse_u32(num, prop_clause)?),
        "reps" => PropertyKind::Reps(parse_u32(num, prop_clause)?),
        "lapses" => PropertyKind::Lapses(parse_u32(num, prop_clause)?),
        "pos" => PropertyKind::Position(parse_u32(num, prop_clause)?),
        "s" => PropertyKind::Stability(parse_f32(num, prop_clause)?),
        "d" => PropertyKind::Difficulty(parse_f32(num, prop_clause)?),
        "r" => PropertyKind::Retrievability(parse_f32(num, prop_clause)?),
        prop if prop.starts_with("cdn:") => PropertyKind::CustomDataNumber {
            key: prop.strip_prefix("cdn:").unwrap().into(),
            value: parse_f32(num, prop_clause)?,
        },
        prop if prop.starts_with("cds:") => PropertyKind::CustomDataString {
            key: prop.strip_prefix("cds:").unwrap().into(),
            value: num.into(),
        },
        _ => unreachable!(),
    };

    Ok(SearchNode::Property {
        operator: operator.to_string(),
        kind,
    })
}

fn parse_u32<'a>(num: &str, context: &'a str) -> ParseResult<'a, u32> {
    num.parse().map_err(|_e| {
        parse_failure(
            context,
            FailKind::InvalidPositiveWholeNumber {
                context: context.into(),
                provided: num.into(),
            },
        )
    })
}

fn parse_i32<'a>(num: &str, context: &'a str) -> ParseResult<'a, i32> {
    num.parse().map_err(|_e| {
        parse_failure(
            context,
            FailKind::InvalidWholeNumber {
                context: context.into(),
                provided: num.into(),
            },
        )
    })
}

fn parse_negative_i32<'a>(num: &str, context: &'a str) -> ParseResult<'a, i32> {
    num.parse()
        .map_err(|_| ())
        .and_then(|n| if n > 0 { Err(()) } else { Ok(n) })
        .map_err(|_| {
            parse_failure(
                context,
                FailKind::InvalidNegativeWholeNumber {
                    context: context.into(),
                    provided: num.into(),
                },
            )
        })
}

fn parse_f32<'a>(num: &str, context: &'a str) -> ParseResult<'a, f32> {
    num.parse().map_err(|_e| {
        parse_failure(
            context,
            FailKind::InvalidNumber {
                context: context.into(),
                provided: num.into(),
            },
        )
    })
}

fn parse_i64<'a>(num: &str, context: &'a str) -> ParseResult<'a, i64> {
    num.parse().map_err(|_e| {
        parse_failure(
            context,
            FailKind::InvalidWholeNumber {
                context: context.into(),
                provided: num.into(),
            },
        )
    })
}

fn parse_answer_button<'a>(num: Option<&str>, context: &'a str) -> ParseResult<'a, RatingKind> {
    Ok(if let Some(num) = num {
        RatingKind::AnswerButton(
            num.parse()
                .map_err(|_| ())
                .and_then(|n| if matches!(n, 1..=4) { Ok(n) } else { Err(()) })
                .map_err(|_| {
                    parse_failure(
                        context,
                        FailKind::InvalidAnswerButton {
                            context: context.into(),
                            provided: num.into(),
                        },
                    )
                })?,
        )
    } else {
        RatingKind::AnyAnswerButton
    })
}

fn parse_prop_rated<'a>(num: &str, context: &'a str) -> ParseResult<'a, PropertyKind> {
    let mut it = num.splitn(2, ':');
    let days = parse_negative_i32(it.next().unwrap(), context)?;
    let button = parse_answer_button(it.next(), context)?;
    Ok(PropertyKind::Rated(days, button))
}

/// eg added:1
fn parse_added(s: &str) -> ParseResult<'_, SearchNode> {
    parse_u32(s, "added:").map(|n| SearchNode::AddedInDays(n.max(1)))
}

/// eg edited:1
fn parse_edited(s: &str) -> ParseResult<'_, SearchNode> {
    parse_u32(s, "edited:").map(|n| SearchNode::EditedInDays(n.max(1)))
}

/// eg introduced:1
fn parse_introduced(s: &str) -> ParseResult<'_, SearchNode> {
    parse_u32(s, "introduced:").map(|n| SearchNode::IntroducedInDays(n.max(1)))
}

/// eg rated:3 or rated:10:2
/// second arg must be between 1-4
fn parse_rated(s: &str) -> ParseResult<'_, SearchNode> {
    let mut it = s.splitn(2, ':');
    let days = parse_u32(it.next().unwrap(), "rated:")?.max(1);
    let button = parse_answer_button(it.next(), s)?;
    Ok(SearchNode::Rated { days, ease: button })
}

/// eg is:due
fn parse_state(s: &str) -> ParseResult<'_, SearchNode> {
    use StateKind::*;
    Ok(SearchNode::State(match s {
        "new" => New,
        "review" => Review,
        "learn" => Learning,
        "due" => Due,
        "buried" => Buried,
        "buried-manually" => UserBuried,
        "buried-sibling" => SchedBuried,
        "suspended" => Suspended,
        _ => {
            return Err(parse_failure(
                s,
                FailKind::InvalidState { provided: s.into() },
            ));
        }
    }))
}

fn parse_mid(s: &str) -> ParseResult<'_, SearchNode> {
    parse_i64(s, "mid:").map(|n| SearchNode::NotetypeId(n.into()))
}

/// ensure a list of ids contains only numbers and commas, returning unchanged
/// if true used by nid: and cid:
fn check_id_list<'a>(s: &'a str, context: &str) -> ParseResult<'a, &'a str> {
    static RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^(\d+,)*\d+$").unwrap());
    if RE.is_match(s) {
        Ok(s)
    } else {
        Err(parse_failure(
            s,
            // id lists are undocumented, so no translation
            FailKind::Other {
                info: Some(format!("expected only digits and commas in {context}:")),
            },
        ))
    }
}

/// eg dupe:1231,hello
fn parse_dupe(s: &str) -> ParseResult<'_, SearchNode> {
    let mut it = s.splitn(2, ',');
    let ntid = parse_i64(it.next().unwrap(), s)?;
    if let Some(text) = it.next() {
        Ok(SearchNode::Duplicates {
            notetype_id: ntid.into(),
            text: unescape_quotes_and_backslashes(text),
        })
    } else {
        // this is an undocumented keyword, so no translation/help
        Err(parse_failure(
            s,
            FailKind::Other {
                info: Some("invalid 'dupe:' search".into()),
            },
        ))
    }
}

fn parse_single_field<'a>(key: &'a str, val: &'a str) -> ParseResult<'a, SearchNode> {
    Ok(if let Some(stripped) = val.strip_prefix("re:") {
        SearchNode::SingleField {
            field: unescape(key)?,
            text: unescape_quotes(stripped),
            mode: FieldSearchMode::Regex,
        }
    } else if let Some(stripped) = val.strip_prefix("nc:") {
        SearchNode::SingleField {
            field: unescape(key)?,
            text: unescape_quotes(stripped),
            mode: FieldSearchMode::NoCombining,
        }
    } else {
        SearchNode::SingleField {
            field: unescape(key)?,
            text: unescape(val)?,
            mode: FieldSearchMode::Normal,
        }
    })
}

/// For strings without unescaped ", convert \" to "
pub(super) fn unescape_quotes(s: &str) -> String {
    if s.contains('"') {
        s.replace(r#"\""#, "\"")
    } else {
        s.into()
    }
}

/// For non-globs like dupe text without any assumption about the content
fn unescape_quotes_and_backslashes(s: &str) -> String {
    if s.contains('"') || s.contains('\\') {
        s.replace(r#"\""#, "\"").replace(r"\\", r"\")
    } else {
        s.into()
    }
}

/// Unescape chars with special meaning to the parser.
pub(super) fn unescape(txt: &str) -> ParseResult<'_, String> {
    if let Some(seq) = invalid_escape_sequence(txt) {
        Err(parse_failure(
            txt,
            FailKind::UnknownEscape { provided: seq },
        ))
    } else {
        Ok(if is_parser_escape(txt) {
            static RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r#"\\[\\":()-]"#).unwrap());
            RE.replace_all(txt, |caps: &Captures| match &caps[0] {
                r"\\" => r"\\",
                "\\\"" => "\"",
                r"\:" => ":",
                r"\(" => "(",
                r"\)" => ")",
                r"\-" => "-",
                _ => unreachable!(),
            })
            .into()
        } else {
            txt.into()
        })
    }
}

/// Return invalid escape sequence if any.
fn invalid_escape_sequence(txt: &str) -> Option<String> {
    // odd number of \s not followed by an escapable character
    static RE: LazyLock<Regex> = LazyLock::new(|| {
        Regex::new(
            r#"(?x)
            (?:^|[^\\])         # not a backslash
            (?:\\\\)*           # even number of backslashes
            (\\                 # single backslash
            (?:[^\\":*_()-]|$)) # anything but an escapable char
            "#,
        )
        .unwrap()
    });
    let caps = RE.captures(txt)?;

    Some(caps[1].to_string())
}

/// Check string for escape sequences handled by the parser: ":()-
fn is_parser_escape(txt: &str) -> bool {
    // odd number of \s followed by a char with special meaning to the parser
    static RE: LazyLock<Regex> = LazyLock::new(|| {
        Regex::new(
            r#"(?x)
            (?:^|[^\\])     # not a backslash
            (?:\\\\)*       # even number of backslashes
            \\              # single backslash
            [":()-]         # parser escape
            "#,
        )
        .unwrap()
    });

    RE.is_match(txt)
}
