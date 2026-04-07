// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

use std::ops::Range;

use super::super::parser::Node;
use super::super::parser::SearchNode;

#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum RequiredTable {
    Notes,
    Cards,
    CardsAndNotes,
    CardsOrNotes,
}

impl RequiredTable {
    pub(super) fn combine(self, other: RequiredTable) -> RequiredTable {
        match (self, other) {
            (RequiredTable::CardsAndNotes, _) => RequiredTable::CardsAndNotes,
            (_, RequiredTable::CardsAndNotes) => RequiredTable::CardsAndNotes,
            (RequiredTable::CardsOrNotes, b) => b,
            (a, RequiredTable::CardsOrNotes) => a,
            (a, b) => {
                if a == b {
                    a
                } else {
                    RequiredTable::CardsAndNotes
                }
            }
        }
    }
}

/// Given a list of numbers, create one or more ranges, collapsing
/// contiguous numbers.
pub(crate) trait CollectRanges {
    type Item;
    fn collect_ranges(self, join: bool) -> Vec<Range<Self::Item>>;
}

impl<
    Idx: Copy + PartialOrd + std::ops::Add<Idx, Output = Idx> + From<u8>,
    I: IntoIterator<Item = Idx>,
> CollectRanges for I
{
    type Item = Idx;

    fn collect_ranges(self, join: bool) -> Vec<Range<Self::Item>> {
        let mut result = Vec::new();
        let mut iter = self.into_iter();
        let next = iter.next();
        if next.is_none() {
            return result;
        }
        let mut start = next.unwrap();
        let mut end = next.unwrap();

        for i in iter {
            if join && i == end + 1.into() {
                end = end + 1.into();
            } else {
                result.push(start..end + 1.into());
                start = i;
                end = i;
            }
        }
        result.push(start..end + 1.into());

        result
    }
}

pub(super) struct FieldQualifiedSearchContext {
    pub(super) ntid: crate::notetype::NotetypeId,
    pub(super) total_fields_in_note: usize,
    /// This may include more than one field in the case the user
    /// has searched with a wildcard, eg f*:foo.
    pub(super) field_ranges_to_search: Vec<Range<u32>>,
}

pub(super) struct UnqualifiedSearchContext {
    pub(super) ntid: crate::notetype::NotetypeId,
    pub(super) total_fields_in_note: usize,
    pub(super) sortf_excluded: bool,
    pub(super) field_ranges_to_search: Vec<Range<u32>>,
}

pub(super) struct UnqualifiedRegexSearchContext {
    pub(super) ntid: crate::notetype::NotetypeId,
    pub(super) total_fields_in_note: usize,
    /// Unlike the other contexts, this contains each individual index
    /// instead of a list of ranges.
    pub(super) fields_to_search: Vec<u32>,
}

impl Node {
    pub(super) fn required_table(&self) -> RequiredTable {
        match self {
            Node::And => RequiredTable::CardsOrNotes,
            Node::Or => RequiredTable::CardsOrNotes,
            Node::Not(node) => node.required_table(),
            Node::Group(nodes) => nodes.iter().fold(RequiredTable::CardsOrNotes, |cur, node| {
                cur.combine(node.required_table())
            }),
            Node::Search(node) => node.required_table(),
        }
    }
}

impl SearchNode {
    pub(super) fn required_table(&self) -> RequiredTable {
        match self {
            SearchNode::AddedInDays(_) => RequiredTable::Cards,
            SearchNode::IntroducedInDays(_) => RequiredTable::Cards,
            SearchNode::Deck(_) => RequiredTable::Cards,
            SearchNode::DeckIdsWithoutChildren(_) => RequiredTable::Cards,
            SearchNode::DeckIdWithChildren(_) => RequiredTable::Cards,
            SearchNode::Rated { .. } => RequiredTable::Cards,
            SearchNode::State(_) => RequiredTable::Cards,
            SearchNode::Flag(_) => RequiredTable::Cards,
            SearchNode::CardIds(_) => RequiredTable::Cards,
            SearchNode::Property { .. } => RequiredTable::Cards,
            SearchNode::CustomData { .. } => RequiredTable::Cards,
            SearchNode::Preset(_) => RequiredTable::Cards,

            SearchNode::UnqualifiedText(_) => RequiredTable::Notes,
            SearchNode::SingleField { .. } => RequiredTable::Notes,
            SearchNode::Tag { .. } => RequiredTable::Notes,
            SearchNode::Duplicates { .. } => RequiredTable::Notes,
            SearchNode::Regex(_) => RequiredTable::Notes,
            SearchNode::NoCombining(_) => RequiredTable::Notes,
            SearchNode::StripClozes(_) => RequiredTable::Notes,
            SearchNode::WordBoundary(_) => RequiredTable::Notes,
            SearchNode::NotetypeId(_) => RequiredTable::Notes,
            SearchNode::Notetype(_) => RequiredTable::Notes,
            SearchNode::EditedInDays(_) => RequiredTable::Notes,

            SearchNode::NoteIds(_) => RequiredTable::CardsOrNotes,
            SearchNode::WholeCollection => RequiredTable::CardsOrNotes,

            SearchNode::CardTemplate(_) => RequiredTable::CardsAndNotes,
        }
    }
}
