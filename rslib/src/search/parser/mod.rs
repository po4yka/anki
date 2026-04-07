// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

mod ast;
mod error;
mod filters;
mod lexer;

pub use ast::FieldSearchMode;
pub use ast::Node;
pub use ast::PropertyKind;
pub use ast::RatingKind;
pub use ast::SearchNode;
pub use ast::StateKind;
pub use ast::TemplateKind;

use crate::error::ParseError;
use crate::error::Result;
use crate::error::SearchErrorKind as FailKind;

type IResult<'a, O> = std::result::Result<(&'a str, O), nom::Err<ParseError<'a>>>;
type ParseResult<'a, O> = std::result::Result<O, nom::Err<ParseError<'a>>>;

/// Parse the input string into a list of nodes.
pub fn parse(input: &str) -> Result<Vec<Node>> {
    let input = input.trim();
    if input.is_empty() {
        return Ok(vec![Node::Search(SearchNode::WholeCollection)]);
    }

    match lexer::group_inner(input) {
        Ok(("", nodes)) => Ok(nodes),
        // unmatched ) is only char not consumed by any node parser
        Ok((remaining, _)) => Err(error::parse_failure(remaining, FailKind::UnopenedGroup).into()),
        Err(err) => Err(err.into()),
    }
}

#[cfg(test)]
mod test {
    include!("tests.rs");
}
