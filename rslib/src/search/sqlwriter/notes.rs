// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

use std::borrow::Cow;
use std::fmt::Write;
use std::ops::Range;

use itertools::Itertools;

use super::super::parser::FieldSearchMode;
use super::SqlWriter;
use super::utils::CollectRanges;
use super::utils::FieldQualifiedSearchContext;
use super::utils::UnqualifiedRegexSearchContext;
use super::utils::UnqualifiedSearchContext;
use crate::error::Result;
use crate::notes::field_checksum;
use crate::notetype::NotetypeId;
use crate::storage::ProcessTextFlags;
use crate::storage::ids_to_string;
use crate::text::glob_matcher;
use crate::text::strip_html_preserving_media_filenames;
use crate::text::to_re;
use crate::text::to_sql;
use crate::text::without_combining;

impl SqlWriter<'_> {
    pub(super) fn write_unqualified(
        &mut self,
        text: &str,
        no_combining: bool,
        strip_clozes: bool,
    ) -> Result<()> {
        let text = to_sql(text);
        let text = if no_combining {
            without_combining(&text)
        } else {
            text
        };
        // implicitly wrap in %
        let text = format!("%{text}%");
        self.args.push(text);
        let arg_idx = self.args.len();

        let mut process_text_flags = ProcessTextFlags::empty();
        if no_combining {
            process_text_flags.insert(ProcessTextFlags::NoCombining);
        }
        if strip_clozes {
            process_text_flags.insert(ProcessTextFlags::StripClozes);
        }

        let (sfld_expr, flds_expr) = if !process_text_flags.is_empty() {
            let bits = process_text_flags.bits();
            (
                Cow::from(format!(
                    "coalesce(process_text(cast(n.sfld as text), {bits}), n.sfld)"
                )),
                Cow::from(format!("coalesce(process_text(n.flds, {bits}), n.flds)")),
            )
        } else {
            (Cow::from("n.sfld"), Cow::from("n.flds"))
        };

        if strip_clozes {
            let cloze_notetypes_only_clause = self
                .col
                .get_all_notetypes()?
                .iter()
                .filter(|nt| nt.is_cloze())
                .map(|nt| format!("n.mid = {}", nt.id))
                .join(" or ");
            write!(self.sql, "({cloze_notetypes_only_clause}) and ").unwrap();
        }

        if let Some(field_indicies_by_notetype) = self.included_fields_by_notetype()? {
            let field_idx_str = format!("' || ?{arg_idx} || '");
            let other_idx_str = "%".to_string();

            let notetype_clause = |ctx: &UnqualifiedSearchContext| -> String {
                let field_index_clause = |range: &Range<u32>| {
                    let f = (0..ctx.total_fields_in_note)
                        .filter_map(|i| {
                            if i as u32 == range.start {
                                Some(&field_idx_str)
                            } else if range.contains(&(i as u32)) {
                                None
                            } else {
                                Some(&other_idx_str)
                            }
                        })
                        .join("\x1f");
                    format!("{flds_expr} like '{f}' escape '\\'")
                };
                let mut all_field_clauses: Vec<String> = ctx
                    .field_ranges_to_search
                    .iter()
                    .map(field_index_clause)
                    .collect();
                if !ctx.sortf_excluded {
                    all_field_clauses.push(format!("{sfld_expr} like ?{arg_idx} escape '\\'"));
                }
                format!(
                    "(n.mid = {mid} and ({all_field_clauses}))",
                    mid = ctx.ntid,
                    all_field_clauses = all_field_clauses.join(" or ")
                )
            };
            let all_notetype_clauses = field_indicies_by_notetype
                .iter()
                .map(notetype_clause)
                .join(" or ");
            write!(self.sql, "({all_notetype_clauses})").unwrap();
        } else {
            write!(
                self.sql,
                "({sfld_expr} like ?{arg_idx} escape '\\' or {flds_expr} like ?{arg_idx} escape '\\')"
            )
            .unwrap();
        }

        Ok(())
    }

    pub(super) fn write_tag(&mut self, tag: &str, mode: FieldSearchMode) {
        if mode == FieldSearchMode::Regex {
            self.args.push(format!("(?i){tag}"));
            write!(self.sql, "regexp_tags(?{}, n.tags)", self.args.len()).unwrap();
        } else {
            match tag {
                "none" => {
                    write!(self.sql, "n.tags = ''").unwrap();
                }
                "*" => {
                    write!(self.sql, "true").unwrap();
                }
                s if s.contains(' ') => write!(self.sql, "false").unwrap(),
                text => {
                    let text = if mode == FieldSearchMode::Normal {
                        write!(self.sql, "n.tags regexp ?").unwrap();
                        Cow::from(text)
                    } else {
                        write!(
                            self.sql,
                            "coalesce(process_text(n.tags, {}), n.tags) regexp ?",
                            ProcessTextFlags::NoCombining.bits()
                        )
                        .unwrap();
                        without_combining(text)
                    };
                    let re = &crate::text::to_custom_re(&text, r"\S");
                    self.args.push(format!("(?i).* {re}(::| ).*"));
                }
            }
        }
    }

    pub(super) fn write_field(
        &mut self,
        field_name: &str,
        val: &str,
        mode: FieldSearchMode,
    ) -> Result<()> {
        if matches!(field_name, "*" | "_*" | "*_") {
            if mode == FieldSearchMode::Regex {
                self.write_all_fields_regexp(val);
            } else {
                self.write_all_fields(val);
            }
            Ok(())
        } else if mode == FieldSearchMode::Regex {
            self.write_single_field_regexp(field_name, val)
        } else if mode == FieldSearchMode::NoCombining {
            self.write_single_field_nc(field_name, val)
        } else {
            self.write_single_field(field_name, val)
        }
    }

    fn write_all_fields_regexp(&mut self, val: &str) {
        self.args.push(format!("(?i){val}"));
        write!(self.sql, "regexp_fields(?{}, n.flds)", self.args.len()).unwrap();
    }

    fn write_all_fields(&mut self, val: &str) {
        self.args.push(format!("(?is)^{}$", to_re(val)));
        write!(self.sql, "regexp_fields(?{}, n.flds)", self.args.len()).unwrap();
    }

    fn write_single_field_nc(&mut self, field_name: &str, val: &str) -> Result<()> {
        let field_indicies_by_notetype = self.num_fields_and_fields_indices_by_notetype(
            field_name,
            matches!(val, "*" | "_*" | "*_"),
        )?;
        if field_indicies_by_notetype.is_empty() {
            write!(self.sql, "false").unwrap();
            return Ok(());
        }

        let val = to_sql(val);
        let val = without_combining(&val);
        self.args.push(val.into());
        let arg_idx = self.args.len();
        let field_idx_str = format!("' || ?{arg_idx} || '");
        let other_idx_str = "%".to_string();

        let notetype_clause = |ctx: &FieldQualifiedSearchContext| -> String {
            let field_index_clause = |range: &Range<u32>| {
                let f = (0..ctx.total_fields_in_note)
                    .filter_map(|i| {
                        if i as u32 == range.start {
                            Some(&field_idx_str)
                        } else if range.contains(&(i as u32)) {
                            None
                        } else {
                            Some(&other_idx_str)
                        }
                    })
                    .join("\x1f");
                format!(
                    "coalesce(process_text(n.flds, {}), n.flds) like '{f}' escape '\\'",
                    ProcessTextFlags::NoCombining.bits()
                )
            };

            let all_field_clauses = ctx
                .field_ranges_to_search
                .iter()
                .map(field_index_clause)
                .join(" or ");
            format!("(n.mid = {mid} and ({all_field_clauses}))", mid = ctx.ntid)
        };
        let all_notetype_clauses = field_indicies_by_notetype
            .iter()
            .map(notetype_clause)
            .join(" or ");
        write!(self.sql, "({all_notetype_clauses})").unwrap();

        Ok(())
    }

    fn write_single_field_regexp(&mut self, field_name: &str, val: &str) -> Result<()> {
        let field_indicies_by_notetype = self.fields_indices_by_notetype(field_name)?;
        if field_indicies_by_notetype.is_empty() {
            write!(self.sql, "false").unwrap();
            return Ok(());
        }

        self.args.push(format!("(?i){val}"));
        let arg_idx = self.args.len();

        let all_notetype_clauses = field_indicies_by_notetype
            .iter()
            .map(|(mid, field_indices)| {
                let field_index_list = field_indices.iter().join(", ");
                format!("(n.mid = {mid} and regexp_fields(?{arg_idx}, n.flds, {field_index_list}))")
            })
            .join(" or ");

        write!(self.sql, "({all_notetype_clauses})").unwrap();

        Ok(())
    }

    fn write_single_field(&mut self, field_name: &str, val: &str) -> Result<()> {
        let field_indicies_by_notetype = self.num_fields_and_fields_indices_by_notetype(
            field_name,
            matches!(val, "*" | "_*" | "*_"),
        )?;
        if field_indicies_by_notetype.is_empty() {
            write!(self.sql, "false").unwrap();
            return Ok(());
        }

        self.args.push(to_sql(val).into());
        let arg_idx = self.args.len();
        let field_idx_str = format!("' || ?{arg_idx} || '");
        let other_idx_str = "%".to_string();

        let notetype_clause = |ctx: &FieldQualifiedSearchContext| -> String {
            let field_index_clause = |range: &Range<u32>| {
                let f = (0..ctx.total_fields_in_note)
                    .filter_map(|i| {
                        if i as u32 == range.start {
                            Some(&field_idx_str)
                        } else if range.contains(&(i as u32)) {
                            None
                        } else {
                            Some(&other_idx_str)
                        }
                    })
                    .join("\x1f");
                format!("n.flds like '{f}' escape '\\'")
            };

            let all_field_clauses = ctx
                .field_ranges_to_search
                .iter()
                .map(field_index_clause)
                .join(" or ");
            format!("(n.mid = {mid} and ({all_field_clauses}))", mid = ctx.ntid)
        };
        let all_notetype_clauses = field_indicies_by_notetype
            .iter()
            .map(notetype_clause)
            .join(" or ");
        write!(self.sql, "({all_notetype_clauses})").unwrap();

        Ok(())
    }

    fn num_fields_and_fields_indices_by_notetype(
        &mut self,
        field_name: &str,
        test_for_nonempty: bool,
    ) -> Result<Vec<FieldQualifiedSearchContext>> {
        let matches_glob = glob_matcher(field_name);

        let mut field_map = vec![];
        for nt in self.col.get_all_notetypes()? {
            let matched_fields = nt
                .fields
                .iter()
                .filter(|&field| matches_glob(&field.name))
                .map(|field| field.ord.unwrap_or_default())
                .collect_ranges(!test_for_nonempty);
            if !matched_fields.is_empty() {
                field_map.push(FieldQualifiedSearchContext {
                    ntid: nt.id,
                    total_fields_in_note: nt.fields.len(),
                    field_ranges_to_search: matched_fields,
                });
            }
        }

        // for now, sort the map for the benefit of unit tests
        field_map.sort_by_key(|v| v.ntid);

        Ok(field_map)
    }

    fn fields_indices_by_notetype(
        &mut self,
        field_name: &str,
    ) -> Result<Vec<(NotetypeId, Vec<u32>)>> {
        let matches_glob = glob_matcher(field_name);

        let mut field_map = vec![];
        for nt in self.col.get_all_notetypes()? {
            let matched_fields: Vec<u32> = nt
                .fields
                .iter()
                .filter(|&field| matches_glob(&field.name))
                .map(|field| field.ord.unwrap_or_default())
                .collect();
            if !matched_fields.is_empty() {
                field_map.push((nt.id, matched_fields));
            }
        }

        // for now, sort the map for the benefit of unit tests
        field_map.sort();

        Ok(field_map)
    }

    pub(super) fn included_fields_by_notetype(
        &mut self,
    ) -> Result<Option<Vec<UnqualifiedSearchContext>>> {
        let mut any_excluded = false;
        let mut field_map = vec![];
        for nt in self.col.get_all_notetypes()? {
            let mut sortf_excluded = false;
            let matched_fields = nt
                .fields
                .iter()
                .filter_map(|field| {
                    let ord = field.ord.unwrap_or_default();
                    if field.config.exclude_from_search {
                        any_excluded = true;
                        sortf_excluded |= ord == nt.config.sort_field_idx;
                        return None;
                    }
                    (!field.config.exclude_from_search).then_some(ord)
                })
                .collect_ranges(true);
            if !matched_fields.is_empty() {
                field_map.push(UnqualifiedSearchContext {
                    ntid: nt.id,
                    total_fields_in_note: nt.fields.len(),
                    sortf_excluded,
                    field_ranges_to_search: matched_fields,
                });
            }
        }
        if any_excluded {
            Ok(Some(field_map))
        } else {
            Ok(None)
        }
    }

    pub(super) fn included_fields_for_unqualified_regex(
        &mut self,
    ) -> Result<Option<Vec<UnqualifiedRegexSearchContext>>> {
        let mut any_excluded = false;
        let mut field_map = vec![];
        for nt in self.col.get_all_notetypes()? {
            let matched_fields: Vec<u32> = nt
                .fields
                .iter()
                .filter_map(|field| {
                    any_excluded |= field.config.exclude_from_search;
                    (!field.config.exclude_from_search).then_some(field.ord.unwrap_or_default())
                })
                .collect();
            field_map.push(UnqualifiedRegexSearchContext {
                ntid: nt.id,
                total_fields_in_note: nt.fields.len(),
                fields_to_search: matched_fields,
            });
        }
        if any_excluded {
            Ok(Some(field_map))
        } else {
            Ok(None)
        }
    }

    pub(super) fn write_dupe(
        &mut self,
        ntid: crate::notetype::NotetypeId,
        text: &str,
    ) -> Result<()> {
        let text_nohtml = strip_html_preserving_media_filenames(text);
        let csum = field_checksum(text_nohtml.as_ref());

        let nids: Vec<_> = self
            .col
            .storage
            .note_fields_by_checksum(ntid, csum)?
            .into_iter()
            .filter_map(|(nid, field)| {
                if strip_html_preserving_media_filenames(&field) == text_nohtml {
                    Some(nid)
                } else {
                    None
                }
            })
            .collect();

        self.sql += "n.id in ";
        ids_to_string(&mut self.sql, &nids);

        Ok(())
    }

    pub(super) fn write_regex(&mut self, word: &str, no_combining: bool) -> Result<()> {
        let flds_expr = if no_combining {
            Cow::from(format!(
                "coalesce(process_text(n.flds, {}), n.flds)",
                ProcessTextFlags::NoCombining.bits()
            ))
        } else {
            Cow::from("n.flds")
        };
        let word = if no_combining {
            without_combining(word)
        } else {
            std::borrow::Cow::Borrowed(word)
        };
        self.args.push(format!(r"(?i){word}"));
        let arg_idx = self.args.len();
        if let Some(field_indices_by_notetype) = self.included_fields_for_unqualified_regex()? {
            let notetype_clause = |ctx: &UnqualifiedRegexSearchContext| -> String {
                let clause = if ctx.fields_to_search.len() == ctx.total_fields_in_note {
                    format!("{flds_expr} regexp ?{arg_idx}")
                } else {
                    let indices = ctx.fields_to_search.iter().join(",");
                    format!("regexp_fields(?{arg_idx}, {flds_expr}, {indices})")
                };

                format!("(n.mid = {mid} and {clause})", mid = ctx.ntid)
            };
            let all_notetype_clauses = field_indices_by_notetype
                .iter()
                .map(notetype_clause)
                .join(" or ");
            write!(self.sql, "({all_notetype_clauses})").unwrap();
        } else {
            write!(self.sql, "{flds_expr} regexp ?{arg_idx}").unwrap();
        }

        Ok(())
    }

    pub(super) fn write_word_boundary(&mut self, word: &str) -> Result<()> {
        let re = format!(r"\b{}\b", to_re(word));
        self.write_regex(
            &re,
            self.col
                .get_config_bool(crate::prelude::BoolKey::IgnoreAccentsInSearch),
        )
    }
}
