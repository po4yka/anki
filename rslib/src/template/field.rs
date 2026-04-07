// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

use std::collections::HashMap;
use std::collections::HashSet;
use std::fmt::Write;
use std::iter;

use super::parser::ParsedNode;
use super::parser::ParsedTemplate;

// Checking if template is empty
//----------------------------------------

impl ParsedTemplate {
    /// true if provided fields are sufficient to render the template
    pub fn renders_with_fields(&self, nonempty_fields: &HashSet<&str>) -> bool {
        !template_is_empty(nonempty_fields, &self.0, true)
    }

    pub fn renders_with_fields_for_reqs(&self, nonempty_fields: &HashSet<&str>) -> bool {
        !template_is_empty(nonempty_fields, &self.0, false)
    }
}

/// If check_negated is false, negated conditionals resolve to their children,
/// even if the referenced key is non-empty. This allows the legacy required
/// field cache to generate results closer to older Anki versions.
fn template_is_empty(
    nonempty_fields: &HashSet<&str>,
    nodes: &[ParsedNode],
    check_negated: bool,
) -> bool {
    use ParsedNode::*;
    for node in nodes {
        match node {
            // ignore normal text
            Text(_) | Comment(_) => (),
            Replacement { key, .. } => {
                if nonempty_fields.contains(key.as_str()) {
                    // a single replacement is enough
                    return false;
                }
            }
            Conditional { key, children } => {
                if !nonempty_fields.contains(key.as_str()) {
                    continue;
                }
                if !template_is_empty(nonempty_fields, children, check_negated) {
                    return false;
                }
            }
            NegatedConditional { key, children } => {
                if check_negated && nonempty_fields.contains(key.as_str()) {
                    continue;
                }

                if !template_is_empty(nonempty_fields, children, check_negated) {
                    return false;
                }
            }
        }
    }

    true
}

// Field requirements
//----------------------------------------

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FieldRequirements {
    Any(HashSet<u16>),
    All(HashSet<u16>),
    None,
}

pub type FieldMap<'a> = HashMap<&'a str, u16>;

impl ParsedTemplate {
    /// Return fields required by template.
    ///
    /// This is not able to represent negated expressions or combinations of
    /// Any and All, but is compatible with older Anki clients.
    ///
    /// In the future, it may be feasible to calculate the requirements
    /// when adding cards, instead of caching them up front, which would mean
    /// the above restrictions could be lifted. We would probably
    /// want to add a cache of non-zero fields -> available cards to avoid
    /// slowing down bulk operations like importing too much.
    pub fn requirements(&self, field_map: &FieldMap) -> FieldRequirements {
        let mut nonempty: HashSet<_> = Default::default();
        let mut ords = HashSet::new();
        for (name, ord) in field_map {
            nonempty.clear();
            nonempty.insert(*name);
            if self.renders_with_fields_for_reqs(&nonempty) {
                ords.insert(*ord);
            }
        }
        if !ords.is_empty() {
            return FieldRequirements::Any(ords);
        }

        nonempty.extend(field_map.keys());
        ords.extend(field_map.values().copied());
        for (name, ord) in field_map {
            // can we remove this field and still render?
            nonempty.remove(name);
            if self.renders_with_fields_for_reqs(&nonempty) {
                ords.remove(ord);
            }
            nonempty.insert(*name);
        }
        if !ords.is_empty() && self.renders_with_fields_for_reqs(&nonempty) {
            FieldRequirements::All(ords)
        } else {
            FieldRequirements::None
        }
    }
}

// Renaming & deleting fields
//----------------------------------------

impl ParsedTemplate {
    /// Given a map of old to new field names, update references to the new
    /// names. Returns true if any changes made.
    pub(crate) fn rename_and_remove_fields(&mut self, fields: &HashMap<String, Option<String>>) {
        let old_nodes = std::mem::take(&mut self.0);
        self.0 = rename_and_remove_fields(old_nodes, fields);
    }

    pub(crate) fn contains_cloze_replacement(&self) -> bool {
        self.0.iter().any(|node| {
            matches!(
                node,
                ParsedNode::Replacement {key:_, filters} if filters.iter().any(|f| f=="cloze")
            )
        })
    }

    pub(crate) fn contains_field_replacement(&self) -> bool {
        let mut set = HashSet::new();
        find_field_references(&self.0, &mut set, false, false);
        !set.is_empty()
    }

    pub(crate) fn add_missing_field_replacement(&mut self, field_name: &str, is_cloze: bool) {
        let key = String::from(field_name);
        let filters = match is_cloze {
            true => vec![String::from("cloze")],
            false => Vec::new(),
        };
        self.0.push(ParsedNode::Replacement { key, filters });
    }
}

fn rename_and_remove_fields(
    nodes: Vec<ParsedNode>,
    fields: &HashMap<String, Option<String>>,
) -> Vec<ParsedNode> {
    let mut out = vec![];
    for node in nodes {
        match node {
            ParsedNode::Text(text) => out.push(ParsedNode::Text(text)),
            ParsedNode::Comment(text) => out.push(ParsedNode::Comment(text)),
            ParsedNode::Replacement { key, filters } => {
                match fields.get(&key) {
                    // delete the field
                    Some(None) => (),
                    // rename it
                    Some(Some(new_name)) => out.push(ParsedNode::Replacement {
                        key: new_name.into(),
                        filters,
                    }),
                    // or leave it alone
                    None => out.push(ParsedNode::Replacement { key, filters }),
                }
            }
            ParsedNode::Conditional { key, children } => {
                let children = rename_and_remove_fields(children, fields);
                match fields.get(&key) {
                    // remove the field, preserving children
                    Some(None) => out.extend(children),
                    // rename it
                    Some(Some(new_name)) => out.push(ParsedNode::Conditional {
                        key: new_name.into(),
                        children,
                    }),
                    // or leave it alone
                    None => out.push(ParsedNode::Conditional { key, children }),
                }
            }
            ParsedNode::NegatedConditional { key, children } => {
                let children = rename_and_remove_fields(children, fields);
                match fields.get(&key) {
                    // remove the field, preserving children
                    Some(None) => out.extend(children),
                    // rename it
                    Some(Some(new_name)) => out.push(ParsedNode::NegatedConditional {
                        key: new_name.into(),
                        children,
                    }),
                    // or leave it alone
                    None => out.push(ParsedNode::NegatedConditional { key, children }),
                }
            }
        }
    }
    out
}

// Writing back to a string
//----------------------------------------

impl ParsedTemplate {
    pub(crate) fn template_to_string(&self) -> String {
        let mut buf = String::new();
        nodes_to_string(&mut buf, &self.0);
        buf
    }
}

fn nodes_to_string(buf: &mut String, nodes: &[ParsedNode]) {
    use super::parser::COMMENT_END;
    use super::parser::COMMENT_START;

    for node in nodes {
        match node {
            ParsedNode::Text(text) => buf.push_str(text),
            ParsedNode::Comment(text) => {
                buf.push_str(COMMENT_START);
                buf.push_str(text);
                buf.push_str(COMMENT_END);
            }
            ParsedNode::Replacement { key, filters } => {
                write!(
                    buf,
                    "{{{{{}}}}}",
                    filters
                        .iter()
                        .rev()
                        .chain(iter::once(key))
                        .map(|s| s.to_string())
                        .collect::<Vec<_>>()
                        .join(":")
                )
                .unwrap();
            }
            ParsedNode::Conditional { key, children } => {
                write!(buf, "{{{{#{key}}}}}").unwrap();
                nodes_to_string(buf, children);
                write!(buf, "{{{{/{key}}}}}").unwrap();
            }
            ParsedNode::NegatedConditional { key, children } => {
                write!(buf, "{{{{^{key}}}}}").unwrap();
                nodes_to_string(buf, children);
                write!(buf, "{{{{/{key}}}}}").unwrap();
            }
        }
    }
}

// Detecting cloze fields
//----------------------------------------

impl ParsedTemplate {
    /// Field names may not be valid.
    pub(crate) fn all_referenced_field_names(&self) -> HashSet<&str> {
        let mut set = HashSet::new();
        find_field_references(&self.0, &mut set, false, true);
        set
    }

    /// Field names may not be valid.
    pub(crate) fn all_referenced_cloze_field_names(&self) -> HashSet<&str> {
        let mut set = HashSet::new();
        find_field_references(&self.0, &mut set, true, false);
        set
    }
}

fn find_field_references<'a>(
    nodes: &'a [ParsedNode],
    fields: &mut HashSet<&'a str>,
    cloze_only: bool,
    with_conditionals: bool,
) {
    for node in nodes {
        match node {
            ParsedNode::Text(_) => {}
            ParsedNode::Comment(_) => {}
            ParsedNode::Replacement { key, filters } => {
                if !cloze_only || filters.iter().any(|f| f == "cloze") {
                    fields.insert(key);
                }
            }
            ParsedNode::Conditional { key, children }
            | ParsedNode::NegatedConditional { key, children } => {
                if with_conditionals && !is_cloze_conditional(key) {
                    fields.insert(key);
                }
                find_field_references(children, fields, cloze_only, with_conditionals);
            }
        }
    }
}

pub(super) fn is_cloze_conditional(key: &str) -> bool {
    key.strip_prefix('c')
        .is_some_and(|s| s.parse::<u32>().is_ok())
}
