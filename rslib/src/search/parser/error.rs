// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

use crate::error::ParseError;
use crate::error::SearchErrorKind as FailKind;

pub(super) fn parse_failure(input: &str, kind: FailKind) -> nom::Err<ParseError<'_>> {
    nom::Err::Failure(ParseError::Anki(input, kind))
}

pub(super) fn parse_error(input: &str) -> nom::Err<ParseError<'_>> {
    nom::Err::Error(ParseError::Anki(input, FailKind::Other { info: None }))
}
