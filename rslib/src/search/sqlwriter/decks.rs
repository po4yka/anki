// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

use std::fmt::Write;

use super::super::parser::TemplateKind;
use super::SqlWriter;
use crate::decks::NativeDeckName;
use crate::error::Result;
use crate::prelude::DeckId;
use crate::storage::ids_to_string;
use crate::text::is_glob;
use crate::text::to_re;
use crate::text::to_text;

impl SqlWriter<'_> {
    pub(super) fn write_deck(&mut self, deck: &str) -> Result<()> {
        match deck {
            "*" => write!(self.sql, "true").unwrap(),
            "filtered" => write!(self.sql, "c.odid != 0").unwrap(),
            deck => {
                // rewrite "current" to the current deck name
                let native_deck = if deck == "current" {
                    let current_did = self.col.get_current_deck_id();
                    regex::escape(
                        self.col
                            .storage
                            .get_deck(current_did)?
                            .map(|d| d.name)
                            .unwrap_or_else(|| NativeDeckName::from_native_str("Default"))
                            .as_native_str(),
                    )
                } else {
                    NativeDeckName::from_human_name(to_re(deck))
                        .as_native_str()
                        .to_string()
                };

                // convert to a regex that includes child decks
                self.args.push(format!("(?i)^{native_deck}($|\x1f)"));
                let arg_idx = self.args.len();
                self.sql.push_str(&format!(concat!(
                    "(c.did in (select id from decks where name regexp ?{n})",
                    " or (c.odid != 0 and c.odid in (select id from decks where name regexp ?{n})))"),
                    n=arg_idx
                ));
            }
        };
        Ok(())
    }

    pub(super) fn write_deck_id_with_children(&mut self, deck_id: DeckId) -> Result<()> {
        if let Some(parent) = self.col.get_deck(deck_id)? {
            let ids = self.col.storage.deck_id_with_children(&parent)?;
            let mut buf = String::new();
            ids_to_string(&mut buf, &ids);
            write!(self.sql, "c.did in {buf}",).unwrap();
        } else {
            self.sql.push_str("false")
        }

        Ok(())
    }

    pub(super) fn write_template(&mut self, template: &TemplateKind) {
        match template {
            TemplateKind::Ordinal(n) => {
                write!(self.sql, "c.ord = {n}").unwrap();
            }
            TemplateKind::Name(name) => {
                if is_glob(name) {
                    let re = format!("(?i)^{}$", to_re(name));
                    self.sql.push_str(
                        "(n.mid,c.ord) in (select ntid,ord from templates where name regexp ?)",
                    );
                    self.args.push(re);
                } else {
                    self.sql.push_str(
                        "(n.mid,c.ord) in (select ntid,ord from templates where name = ?)",
                    );
                    self.args.push(to_text(name).into());
                }
            }
        };
    }

    pub(super) fn write_notetype(&mut self, nt_name: &str) {
        if is_glob(nt_name) {
            let re = format!("(?i)^{}$", to_re(nt_name));
            self.sql
                .push_str("n.mid in (select id from notetypes where name regexp ?)");
            self.args.push(re);
        } else {
            self.sql
                .push_str("n.mid in (select id from notetypes where name = ?)");
            self.args.push(to_text(nt_name).into());
        }
    }

    pub(super) fn write_deck_preset(&mut self, name: &str) -> Result<()> {
        let dcid = self.col.storage.get_deck_config_id_by_name(name)?;
        if dcid.is_none() {
            write!(self.sql, "false").unwrap();
            return Ok(());
        };

        let mut str_ids = String::new();
        let deck_ids = self
            .col
            .storage
            .get_all_decks()?
            .into_iter()
            .filter_map(|d| {
                if d.config_id() == dcid {
                    Some(d.id)
                } else {
                    None
                }
            });
        ids_to_string(&mut str_ids, deck_ids);
        write!(self.sql, "(c.did in {str_ids} or c.odid in {str_ids})").unwrap();
        Ok(())
    }
}
