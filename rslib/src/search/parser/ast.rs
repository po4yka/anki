// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

use anki_proto::search::search_node::FieldSearchMode as FieldSearchModeProto;

use crate::prelude::*;

#[derive(Debug, PartialEq, Clone)]
pub enum Node {
    And,
    Or,
    Not(Box<Node>),
    Group(Vec<Node>),
    Search(SearchNode),
}

#[derive(Copy, Debug, PartialEq, Eq, Clone)]
pub enum FieldSearchMode {
    Normal,
    Regex,
    NoCombining,
}

impl From<FieldSearchModeProto> for FieldSearchMode {
    fn from(mode: FieldSearchModeProto) -> Self {
        match mode {
            FieldSearchModeProto::Normal => Self::Normal,
            FieldSearchModeProto::Regex => Self::Regex,
            FieldSearchModeProto::Nocombining => Self::NoCombining,
        }
    }
}

#[derive(Debug, PartialEq, Clone)]
pub enum SearchNode {
    // text without a colon
    UnqualifiedText(String),
    // foo:bar, where foo doesn't match a term below
    SingleField {
        field: String,
        text: String,
        mode: FieldSearchMode,
    },
    AddedInDays(u32),
    EditedInDays(u32),
    CardTemplate(TemplateKind),
    Deck(String),
    /// Matches cards in a list of deck ids. Cards are matched even if they are
    /// in a filtered deck.
    DeckIdsWithoutChildren(String),
    /// Matches cards in a deck or its children (original_deck_id is not
    /// checked, so filtered cards are not matched).
    DeckIdWithChildren(DeckId),
    IntroducedInDays(u32),
    NotetypeId(NotetypeId),
    Notetype(String),
    Rated {
        days: u32,
        ease: RatingKind,
    },
    Tag {
        tag: String,
        mode: FieldSearchMode,
    },
    Duplicates {
        notetype_id: NotetypeId,
        text: String,
    },
    State(StateKind),
    Flag(u8),
    NoteIds(String),
    CardIds(String),
    Property {
        operator: String,
        kind: PropertyKind,
    },
    WholeCollection,
    Regex(String),
    NoCombining(String),
    StripClozes(String),
    WordBoundary(String),
    CustomData(String),
    Preset(String),
}

#[derive(Debug, PartialEq, Clone)]
pub enum PropertyKind {
    Due(i32),
    Interval(u32),
    Reps(u32),
    Lapses(u32),
    Ease(f32),
    Position(u32),
    Rated(i32, RatingKind),
    Stability(f32),
    Difficulty(f32),
    Retrievability(f32),
    CustomDataNumber { key: String, value: f32 },
    CustomDataString { key: String, value: String },
}

#[derive(Debug, PartialEq, Eq, Clone)]
pub enum StateKind {
    New,
    Review,
    Learning,
    Due,
    Buried,
    UserBuried,
    SchedBuried,
    Suspended,
}

#[derive(Debug, PartialEq, Eq, Clone)]
pub enum TemplateKind {
    Ordinal(u16),
    Name(String),
}

#[derive(Debug, PartialEq, Eq, Clone)]
pub enum RatingKind {
    AnswerButton(u8),
    AnyAnswerButton,
    ManualReschedule,
}
