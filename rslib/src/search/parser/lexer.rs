// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

use nom::Parser;
use nom::branch::alt;
use nom::bytes::complete::escaped;
use nom::bytes::complete::is_not;
use nom::character::complete::anychar;
use nom::character::complete::char;
use nom::character::complete::none_of;
use nom::character::complete::one_of;
use nom::combinator::map;
use nom::multi::many0;
use nom::sequence::preceded;
use nom::sequence::separated_pair;

use super::IResult;
use super::ast::Node;
use super::error::parse_error;
use super::error::parse_failure;
use crate::error::ParseError;
use super::filters::search_node_for_text;
use super::filters::search_node_for_text_with_argument;
use crate::error::SearchErrorKind as FailKind;

pub(super) fn whitespace0(s: &str) -> IResult<'_, Vec<char>> {
    many0(one_of(" \u{3000}")).parse(s)
}

/// Optional leading space, then a (negated) group or text
pub(super) fn node(s: &str) -> IResult<'_, Node> {
    preceded(whitespace0, alt((negated_node, group, text))).parse(s)
}

fn negated_node(s: &str) -> IResult<'_, Node> {
    map(preceded(char('-'), alt((group, text))), |node| {
        Node::Not(Box::new(node))
    })
    .parse(s)
}

/// One or more nodes surrounded by brackets, eg (one OR two)
pub(super) fn group(s: &str) -> IResult<'_, Node> {
    let (opened, _) = char('(')(s)?;
    let (tail, inner) = group_inner(opened)?;
    if let Some(remaining) = tail.strip_prefix(')') {
        if inner.is_empty() {
            Err(parse_failure(s, FailKind::EmptyGroup))
        } else {
            Ok((remaining, Node::Group(inner)))
        }
    } else {
        Err(parse_failure(s, FailKind::UnclosedGroup))
    }
}

/// Either quoted or unquoted text
fn text(s: &str) -> IResult<'_, Node> {
    alt((quoted_term, partially_quoted_term, unquoted_term)).parse(s)
}

/// Quoted text, including the outer double quotes.
fn quoted_term(s: &str) -> IResult<'_, Node> {
    let (remaining, term) = quoted_term_str(s)?;
    Ok((remaining, Node::Search(search_node_for_text(term)?)))
}

/// eg deck:"foo bar" - quotes must come after the :
fn partially_quoted_term(s: &str) -> IResult<'_, Node> {
    let (remaining, (key, val)) = separated_pair(
        escaped(is_not("\"(): \u{3000}\\"), '\\', none_of(" \u{3000}")),
        char(':'),
        quoted_term_str,
    )
    .parse(s)?;
    Ok((
        remaining,
        Node::Search(search_node_for_text_with_argument(key, val)?),
    ))
}

/// Unquoted text, terminated by whitespace or unescaped ", ( or )
fn unquoted_term(s: &str) -> IResult<'_, Node> {
    use nom::error::ErrorKind as NomErrorKind;
    match escaped(is_not("\"() \u{3000}\\"), '\\', none_of(" \u{3000}"))(s) {
        Ok((tail, term)) => {
            if term.is_empty() {
                Err(parse_error(s))
            } else if term.eq_ignore_ascii_case("and") {
                Ok((tail, Node::And))
            } else if term.eq_ignore_ascii_case("or") {
                Ok((tail, Node::Or))
            } else {
                Ok((tail, Node::Search(search_node_for_text(term)?)))
            }
        }
        Err(err) => {
            if let nom::Err::Error((c, NomErrorKind::NoneOf)) = err {
                Err(parse_failure(
                    s,
                    FailKind::UnknownEscape {
                        provided: format!("\\{c}"),
                    },
                ))
            } else if "\"() \u{3000}".contains(s.chars().next().unwrap()) {
                Err(parse_error(s))
            } else {
                // input ends in an odd number of backslashes
                Err(parse_failure(
                    s,
                    FailKind::UnknownEscape {
                        provided: '\\'.to_string(),
                    },
                ))
            }
        }
    }
}

/// Non-empty string delimited by unescaped double quotes.
pub(super) fn quoted_term_str(s: &str) -> IResult<'_, &str> {
    let (opened, _) = char('"')(s)?;
    if let Ok((tail, inner)) =
        escaped::<_, ParseError, _, _>(is_not(r#""\"#), '\\', anychar).parse(opened)
    {
        if let Ok((remaining, _)) = char::<_, ParseError>('"')(tail) {
            Ok((remaining, inner))
        } else {
            Err(parse_failure(s, FailKind::UnclosedQuote))
        }
    } else {
        Err(parse_failure(
            s,
            match opened.chars().next().unwrap() {
                '"' => FailKind::EmptyQuote,
                // no unescaped " and a trailing \
                _ => FailKind::UnclosedQuote,
            },
        ))
    }
}

/// Zero or more nodes inside brackets, eg 'one OR two -three'.
/// Empty vec must be handled by caller.
pub(super) fn group_inner(input: &str) -> IResult<'_, Vec<Node>> {
    let mut remaining = input;
    let mut nodes = vec![];

    loop {
        match node(remaining) {
            Ok((rem, node)) => {
                remaining = rem;

                if nodes.len() % 2 == 0 {
                    // before adding the node, if the length is even then the node
                    // must not be a boolean
                    if node == Node::And {
                        return Err(parse_failure(input, FailKind::MisplacedAnd));
                    } else if node == Node::Or {
                        return Err(parse_failure(input, FailKind::MisplacedOr));
                    }
                } else {
                    // if the length is odd, the next item must be a boolean. if it's
                    // not, add an implicit and
                    if !matches!(node, Node::And | Node::Or) {
                        nodes.push(Node::And);
                    }
                }
                nodes.push(node);
            }
            Err(e) => match e {
                nom::Err::Error(_) => break,
                _ => return Err(e),
            },
        };
    }

    if let Some(last) = nodes.last() {
        match last {
            Node::And => return Err(parse_failure(input, FailKind::MisplacedAnd)),
            Node::Or => return Err(parse_failure(input, FailKind::MisplacedOr)),
            _ => (),
        }
    }
    let (remaining, _) = whitespace0(remaining)?;

    Ok((remaining, nodes))
}
