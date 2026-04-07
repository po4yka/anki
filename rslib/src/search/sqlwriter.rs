// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

mod cards;
mod decks;
mod notes;
mod utils;

use std::fmt::Write;

use super::ReturnItemType;
use super::parser::Node;
use super::parser::SearchNode;
use super::parser::TemplateKind;
use crate::collection::Collection;
use crate::error::Result;
use crate::prelude::*;

pub(crate) use utils::RequiredTable;

pub(crate) struct SqlWriter<'a> {
    col: &'a mut Collection,
    sql: String,
    item_type: ReturnItemType,
    args: Vec<String>,
    normalize_note_text: bool,
    table: RequiredTable,
}

impl SqlWriter<'_> {
    pub(crate) fn new(col: &mut Collection, item_type: ReturnItemType) -> SqlWriter<'_> {
        let normalize_note_text = col.get_config_bool(BoolKey::NormalizeNoteText);
        let sql = String::new();
        let args = vec![];
        SqlWriter {
            col,
            sql,
            item_type,
            args,
            normalize_note_text,
            table: item_type.required_table(),
        }
    }

    pub(super) fn build_query(
        mut self,
        node: &Node,
        table: RequiredTable,
    ) -> Result<(String, Vec<String>)> {
        self.table = self.table.combine(table.combine(node.required_table()));
        self.write_table_sql();
        self.write_node_to_sql(node)?;
        Ok((self.sql, self.args))
    }

    fn write_table_sql(&mut self) {
        let sql = match self.table {
            RequiredTable::Cards => "select c.id from cards c where ",
            RequiredTable::Notes => "select n.id from notes n where ",
            _ => match self.item_type {
                ReturnItemType::Cards => "select c.id from cards c, notes n where c.nid=n.id and ",
                ReturnItemType::Notes => {
                    "select distinct n.id from cards c, notes n where c.nid=n.id and "
                }
            },
        };
        self.sql.push_str(sql);
    }

    /// As an optimization we can omit the cards or notes tables from
    /// certain queries. For code that specifies a note id, we need to
    /// choose the appropriate column name.
    fn note_id_column(&self) -> &'static str {
        match self.table {
            RequiredTable::Notes | RequiredTable::CardsAndNotes => "n.id",
            RequiredTable::Cards => "c.nid",
            RequiredTable::CardsOrNotes => unreachable!(),
        }
    }

    fn write_node_to_sql(&mut self, node: &Node) -> Result<()> {
        match node {
            Node::And => write!(self.sql, " and ").unwrap(),
            Node::Or => write!(self.sql, " or ").unwrap(),
            Node::Not(node) => {
                write!(self.sql, "not ").unwrap();
                self.write_node_to_sql(node)?;
            }
            Node::Group(nodes) => {
                write!(self.sql, "(").unwrap();
                for node in nodes {
                    self.write_node_to_sql(node)?;
                }
                write!(self.sql, ")").unwrap();
            }
            Node::Search(search) => self.write_search_node_to_sql(search)?,
        };
        Ok(())
    }

    /// Convert search text to NFC if note normalization is enabled.
    fn norm_note<'a>(&self, text: &'a str) -> std::borrow::Cow<'a, str> {
        if self.normalize_note_text {
            crate::text::normalize_to_nfc(text)
        } else {
            text.into()
        }
    }

    // NOTE: when adding any new nodes in the future, make sure that they are either
    // a single search term, or they wrap multiple terms in parentheses, as can
    // be seen in the sql() unit test at the bottom of the file.
    fn write_search_node_to_sql(&mut self, node: &SearchNode) -> Result<()> {
        use crate::text::normalize_to_nfc as norm;
        match node {
            // note fields related
            SearchNode::UnqualifiedText(text) => {
                let text = &self.norm_note(text);
                self.write_unqualified(
                    text,
                    self.col.get_config_bool(BoolKey::IgnoreAccentsInSearch),
                    false,
                )?
            }
            SearchNode::SingleField { field, text, mode } => {
                self.write_field(&norm(field), &self.norm_note(text), *mode)?
            }
            SearchNode::Duplicates { notetype_id, text } => {
                self.write_dupe(*notetype_id, &self.norm_note(text))?
            }
            SearchNode::Regex(re) => self.write_regex(&self.norm_note(re), false)?,
            SearchNode::NoCombining(text) => {
                self.write_unqualified(&self.norm_note(text), true, false)?
            }
            SearchNode::StripClozes(text) => self.write_unqualified(
                &self.norm_note(text),
                self.col.get_config_bool(BoolKey::IgnoreAccentsInSearch),
                true,
            )?,
            SearchNode::WordBoundary(text) => self.write_word_boundary(&self.norm_note(text))?,

            // other
            SearchNode::AddedInDays(days) => self.write_added(*days)?,
            SearchNode::EditedInDays(days) => self.write_edited(*days)?,
            SearchNode::IntroducedInDays(days) => self.write_introduced(*days)?,
            SearchNode::CardTemplate(template) => match template {
                TemplateKind::Ordinal(_) => self.write_template(template),
                TemplateKind::Name(name) => {
                    self.write_template(&TemplateKind::Name(norm(name).into()))
                }
            },
            SearchNode::Deck(deck) => self.write_deck(&norm(deck))?,
            SearchNode::NotetypeId(ntid) => {
                write!(self.sql, "n.mid = {ntid}").unwrap();
            }
            SearchNode::DeckIdsWithoutChildren(dids) => {
                write!(
                    self.sql,
                    "c.did in ({dids}) or (c.odid != 0 and c.odid in ({dids}))"
                )
                .unwrap();
            }
            SearchNode::DeckIdWithChildren(did) => self.write_deck_id_with_children(*did)?,
            SearchNode::Notetype(notetype) => self.write_notetype(&norm(notetype)),
            SearchNode::Rated { days, ease } => self.write_rated(">", -i64::from(*days), ease)?,

            SearchNode::Tag { tag, mode } => self.write_tag(&norm(tag), *mode),
            SearchNode::State(state) => self.write_state(state)?,
            SearchNode::Flag(flag) => {
                write!(self.sql, "(c.flags & 7) == {flag}").unwrap();
            }
            SearchNode::NoteIds(nids) => {
                write!(self.sql, "{} in ({})", self.note_id_column(), nids).unwrap();
            }
            SearchNode::CardIds(cids) => {
                write!(self.sql, "c.id in ({cids})").unwrap();
            }
            SearchNode::Property { operator, kind } => self.write_prop(operator, kind)?,
            SearchNode::CustomData(key) => self.write_custom_data(key)?,
            SearchNode::WholeCollection => write!(self.sql, "true").unwrap(),
            SearchNode::Preset(name) => self.write_deck_preset(name)?,
        };
        Ok(())
    }
}

#[cfg(test)]
mod test {
    use anki_io::write_file;
    use tempfile::tempdir;

    use super::super::parser::parse;
    use super::*;
    use crate::collection::Collection;
    use crate::collection::CollectionBuilder;

    // shortcut
    fn s(req: &mut Collection, search: &str) -> (String, Vec<String>) {
        let node = Node::Group(parse(search).unwrap());
        let mut writer = SqlWriter::new(req, ReturnItemType::Cards);
        writer.table = RequiredTable::Notes.combine(node.required_table());
        writer.write_node_to_sql(&node).unwrap();
        (writer.sql, writer.args)
    }

    #[test]
    fn sql() {
        // re-use the mediacheck .anki2 file for now
        use crate::media::check::test::MEDIACHECK_ANKI2;
        let dir = tempdir().unwrap();
        let col_path = dir.path().join("col.anki2");
        write_file(&col_path, MEDIACHECK_ANKI2).unwrap();

        let mut col = CollectionBuilder::new(col_path).build().unwrap();
        let ctx = &mut col;

        // unqualified search
        assert_eq!(
            s(ctx, "te*st"),
            (
                "((n.sfld like ?1 escape '\\' or n.flds like ?1 escape '\\'))".into(),
                vec!["%te%st%".into()]
            )
        );
        assert_eq!(s(ctx, "te%st").1, vec![r"%te\%st%".to_string()]);
        // user should be able to escape wildcards
        assert_eq!(s(ctx, r"te\*s\_t").1, vec!["%te*s\\_t%".to_string()]);

        // field search
        assert_eq!(
            s(ctx, "front:te*st"),
            (
                concat!(
                    "(((n.mid = 1581236385344 and (n.flds like '' || ?1 || '\u{1f}%' escape '\\')) or ",
                    "(n.mid = 1581236385345 and (n.flds like '' || ?1 || '\u{1f}%\u{1f}%' escape '\\')) or ",
                    "(n.mid = 1581236385346 and (n.flds like '' || ?1 || '\u{1f}%' escape '\\')) or ",
                    "(n.mid = 1581236385347 and (n.flds like '' || ?1 || '\u{1f}%' escape '\\'))))"
                )
                .into(),
                vec!["te%st".into()]
            )
        );
        // field search with regex
        assert_eq!(
            s(ctx, "front:re:te.*st"),
            (
                concat!(
                    "(((n.mid = 1581236385344 and regexp_fields(?1, n.flds, 0)) or ",
                    "(n.mid = 1581236385345 and regexp_fields(?1, n.flds, 0)) or ",
                    "(n.mid = 1581236385346 and regexp_fields(?1, n.flds, 0)) or ",
                    "(n.mid = 1581236385347 and regexp_fields(?1, n.flds, 0))))"
                )
                .into(),
                vec!["(?i)te.*st".into()]
            )
        );
        // field search with no-combine
        assert_eq!(
            s(ctx, "front:nc:frânçais"),
            (
                concat!(
                    "(((n.mid = 1581236385344 and (coalesce(process_text(n.flds, 1), n.flds) like '' || ?1 || '\u{1f}%' escape '\\')) or ",
                    "(n.mid = 1581236385345 and (coalesce(process_text(n.flds, 1), n.flds) like '' || ?1 || '\u{1f}%\u{1f}%' escape '\\')) or ",
                    "(n.mid = 1581236385346 and (coalesce(process_text(n.flds, 1), n.flds) like '' || ?1 || '\u{1f}%' escape '\\')) or ",
                    "(n.mid = 1581236385347 and (coalesce(process_text(n.flds, 1), n.flds) like '' || ?1 || '\u{1f}%' escape '\\'))))"
                )
                .into(),
                vec!["francais".into()]
            )
        );

        // all field search
        assert_eq!(
            s(ctx, "*:te*st"),
            (
                "(regexp_fields(?1, n.flds))".into(),
                vec!["(?is)^te.*st$".into()]
            )
        );
        // all field search with regex
        assert_eq!(
            s(ctx, "*:re:te.*st"),
            (
                "(regexp_fields(?1, n.flds))".into(),
                vec!["(?i)te.*st".into()]
            )
        );

        // added
        let timing = ctx.timing_today().unwrap();
        assert_eq!(
            s(ctx, "added:3").0,
            format!("(c.id > {})", (timing.next_day_at.0 - (86_400 * 3)) * 1_000)
        );
        assert_eq!(s(ctx, "added:0").0, s(ctx, "added:1").0,);

        // introduced
        assert_eq!(
            s(ctx, "introduced:3").0,
            format!(
                concat!(
                    "(((SELECT coalesce(min(id) > {cutoff}, false) FROM revlog WHERE cid = c.id AND ease != 0) ",
                    "AND c.id IN (SELECT cid FROM revlog WHERE id > {cutoff})))"
                ),
                cutoff = (timing.next_day_at.0 - (86_400 * 3)) * 1_000,
            )
        );
        assert_eq!(s(ctx, "introduced:0").0, s(ctx, "introduced:1").0,);

        // deck
        assert_eq!(
            s(ctx, "deck:default"),
            (
                "((c.did in (select id from decks where name regexp ?1) or (c.odid != 0 and \
                c.odid in (select id from decks where name regexp ?1))))"
                    .into(),
                vec!["(?i)^default($|\u{1f})".into()]
            )
        );
        assert_eq!(
            s(ctx, "deck:current").1,
            vec!["(?i)^Default($|\u{1f})".to_string()]
        );
        assert_eq!(s(ctx, "deck:d*").1, vec!["(?i)^d.*($|\u{1f})".to_string()]);
        assert_eq!(s(ctx, "deck:filtered"), ("(c.odid != 0)".into(), vec![],));

        // card
        assert_eq!(
            s(ctx, r#""card:card 1""#),
            (
                "((n.mid,c.ord) in (select ntid,ord from templates where name = ?))".into(),
                vec!["card 1".into()]
            )
        );

        // IDs
        assert_eq!(s(ctx, "mid:3"), ("(n.mid = 3)".into(), vec![]));
        assert_eq!(s(ctx, "nid:3"), ("(n.id in (3))".into(), vec![]));
        assert_eq!(s(ctx, "nid:3,4"), ("(n.id in (3,4))".into(), vec![]));
        assert_eq!(s(ctx, "cid:3,4"), ("(c.id in (3,4))".into(), vec![]));

        // flags
        assert_eq!(s(ctx, "flag:2"), ("((c.flags & 7) == 2)".into(), vec![]));
        assert_eq!(s(ctx, "flag:0"), ("((c.flags & 7) == 0)".into(), vec![]));

        // dupes
        assert_eq!(s(ctx, "dupe:123,test"), ("(n.id in ())".into(), vec![]));

        // tags
        assert_eq!(
            s(ctx, r"tag:one"),
            (
                "(n.tags regexp ?)".into(),
                vec!["(?i).* one(::| ).*".into()]
            )
        );
        assert_eq!(
            s(ctx, r"tag:foo::bar"),
            (
                "(n.tags regexp ?)".into(),
                vec!["(?i).* foo::bar(::| ).*".into()]
            )
        );

        assert_eq!(
            s(ctx, r"tag:o*n\*et%w%oth_re\_e"),
            (
                "(n.tags regexp ?)".into(),
                vec![r"(?i).* o\S*n\*et%w%oth\Sre_e(::| ).*".into()]
            )
        );
        assert_eq!(s(ctx, "tag:none"), ("(n.tags = '')".into(), vec![]));
        assert_eq!(s(ctx, "tag:*"), ("(true)".into(), vec![]));
        assert_eq!(
            s(ctx, "tag:re:.ne|tw."),
            (
                "(regexp_tags(?1, n.tags))".into(),
                vec!["(?i).ne|tw.".into()]
            )
        );

        // state
        assert_eq!(
            s(ctx, "is:suspended").0,
            format!("(c.queue = {})", CardQueue::Suspended as i8)
        );
        assert_eq!(
            s(ctx, "is:new").0,
            format!("(c.type = {})", CardType::New as i8)
        );

        // rated
        assert_eq!(
            s(ctx, "rated:2").0,
            format!(
                "(c.id in (select cid from revlog where id >= {} and ease > 0))",
                (timing.next_day_at.0 - (86_400 * 2)) * 1_000
            )
        );
        assert_eq!(
            s(ctx, "rated:400:1").0,
            format!(
                "(c.id in (select cid from revlog where id >= {} and ease = 1))",
                (timing.next_day_at.0 - (86_400 * 400)) * 1_000
            )
        );
        assert_eq!(s(ctx, "rated:0").0, s(ctx, "rated:1").0);

        // resched
        assert_eq!(
            s(ctx, "resched:400").0,
            format!(
                "(c.id in (select cid from revlog where id >= {} and ease = 0))",
                (timing.next_day_at.0 - (86_400 * 400)) * 1_000
            )
        );

        // props
        assert_eq!(s(ctx, "prop:lapses=3").0, "(lapses = 3)".to_string());
        assert_eq!(s(ctx, "prop:ease>=2.5").0, "(factor >= 2500)".to_string());
        assert_eq!(
            s(ctx, "prop:due!=-1").0,
            format!(
                "(((c.queue in (2,3) and \n                        (case when \
c.odue != 0 then c.odue else c.due end) != {days}) or (c.queue in (1,4) and \n                        (((case when c.odue != 0 then c.odue else c.due end) - {cutoff}) / 86400) != -1)))",
                days = timing.days_elapsed - 1,
                cutoff = timing.next_day_at
            )
        );
        assert_eq!(s(ctx, "prop:rated>-5:3").0, s(ctx, "rated:5:3").0);
        assert_eq!(
            &s(ctx, "prop:cdn:r=1").0,
            "(cast(extract_custom_data(c.data, 'r') as float) = 1)"
        );
        assert_eq!(
            &s(ctx, "prop:cds:r=s").0,
            "(extract_custom_data(c.data, 'r') = 's')"
        );

        // note types by name
        assert_eq!(
            s(ctx, "note:basic"),
            (
                "(n.mid in (select id from notetypes where name = ?))".into(),
                vec!["basic".into()]
            )
        );
        assert_eq!(
            s(ctx, "note:basic*"),
            (
                "(n.mid in (select id from notetypes where name regexp ?))".into(),
                vec!["(?i)^basic.*$".into()]
            )
        );

        // regex
        assert_eq!(
            s(ctx, r"re:\bone"),
            ("(n.flds regexp ?1)".into(), vec![r"(?i)\bone".into()])
        );

        // word boundary
        assert_eq!(
            s(ctx, r"w:foo"),
            ("(n.flds regexp ?1)".into(), vec![r"(?i)\bfoo\b".into()])
        );
        assert_eq!(
            s(ctx, r"w:*foo"),
            ("(n.flds regexp ?1)".into(), vec![r"(?i)\b.*foo\b".into()])
        );

        assert_eq!(
            s(ctx, r"w:*fo_o*"),
            (
                "(n.flds regexp ?1)".into(),
                vec![r"(?i)\b.*fo.o.*\b".into()]
            )
        );

        // has-cd
        assert_eq!(
            &s(ctx, "has-cd:r").0,
            "(extract_custom_data(c.data, 'r') is not null)"
        );

        // preset search
        assert_eq!(
            &s(ctx, "preset:default").0,
            "((c.did in (1) or c.odid in (1)))"
        );
        assert_eq!(&s(ctx, "preset:typo").0, "(false)");

        // strip clozes
        assert_eq!(
            &s(ctx, "sc:abcdef").0,
            "((n.mid = 1581236385343) and (coalesce(process_text(cast(n.sfld as text), 2), n.sfld) like ?1 escape '\\' or coalesce(process_text(n.flds, 2), n.flds) like ?1 escape '\\'))"
        );
    }

    #[test]
    fn required_table() {
        assert_eq!(
            Node::Group(parse("").unwrap()).required_table(),
            RequiredTable::CardsOrNotes
        );
        assert_eq!(
            Node::Group(parse("test").unwrap()).required_table(),
            RequiredTable::Notes
        );
        assert_eq!(
            Node::Group(parse("cid:1").unwrap()).required_table(),
            RequiredTable::Cards
        );
        assert_eq!(
            Node::Group(parse("cid:1 test").unwrap()).required_table(),
            RequiredTable::CardsAndNotes
        );
        assert_eq!(
            Node::Group(parse("nid:1").unwrap()).required_table(),
            RequiredTable::CardsOrNotes
        );
        assert_eq!(
            Node::Group(parse("cid:1 nid:1").unwrap()).required_table(),
            RequiredTable::Cards
        );
        assert_eq!(
            Node::Group(parse("test nid:1").unwrap()).required_table(),
            RequiredTable::Notes
        );
    }

    #[allow(clippy::single_range_in_vec_init)]
    #[test]
    fn ranges() {
        assert_eq!([1, 2, 3].collect_ranges(true), [1..4]);
        assert_eq!([1, 3, 4].collect_ranges(true), [1..2, 3..5]);
        assert_eq!([1, 2, 5, 6].collect_ranges(false), [1..2, 2..3, 5..6, 6..7]);
    }
}
