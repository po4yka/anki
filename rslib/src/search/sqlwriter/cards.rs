// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

use std::fmt::Write;

use super::super::parser::PropertyKind;
use super::super::parser::RatingKind;
use super::super::parser::StateKind;
use super::SqlWriter;
use crate::card::CardQueue;
use crate::card::CardType;
use crate::error::Result;
use crate::timestamp::TimestampSecs;

impl SqlWriter<'_> {
    pub(super) fn write_state(&mut self, state: &StateKind) -> Result<()> {
        let timing = self.col.timing_today()?;
        match state {
            StateKind::New => write!(self.sql, "c.type = {}", CardType::New as i8),
            StateKind::Review => write!(
                self.sql,
                "c.type in ({}, {})",
                CardType::Review as i8,
                CardType::Relearn as i8,
            ),
            StateKind::Learning => write!(
                self.sql,
                "c.type in ({}, {})",
                CardType::Learn as i8,
                CardType::Relearn as i8,
            ),
            StateKind::Buried => write!(
                self.sql,
                "c.queue in ({},{})",
                CardQueue::SchedBuried as i8,
                CardQueue::UserBuried as i8
            ),
            StateKind::Suspended => write!(self.sql, "c.queue = {}", CardQueue::Suspended as i8),
            StateKind::Due => write!(
                self.sql,
                "(\
                (c.queue in ({rev},{daylrn}) and c.due <= {today}) or \
                (c.queue in ({lrn},{previewrepeat}) and c.due <= {learncutoff})\
                )",
                rev = CardQueue::Review as i8,
                daylrn = CardQueue::DayLearn as i8,
                today = timing.days_elapsed,
                lrn = CardQueue::Learn as i8,
                previewrepeat = CardQueue::PreviewRepeat as i8,
                learncutoff = TimestampSecs::now().0 + (self.col.learn_ahead_secs() as i64),
            ),
            StateKind::UserBuried => write!(self.sql, "c.queue = {}", CardQueue::UserBuried as i8),
            StateKind::SchedBuried => {
                write!(self.sql, "c.queue = {}", CardQueue::SchedBuried as i8)
            }
        }
        .unwrap();
        Ok(())
    }

    pub(super) fn write_rated(&mut self, op: &str, days: i64, ease: &RatingKind) -> Result<()> {
        let today_cutoff = self.col.timing_today()?.next_day_at;
        let target_cutoff_ms = today_cutoff.adding_secs(86_400 * days).as_millis();
        let day_before_cutoff_ms = today_cutoff.adding_secs(86_400 * (days - 1)).as_millis();

        write!(self.sql, "c.id in (select cid from revlog where id").unwrap();

        match op {
            ">" => write!(self.sql, " >= {target_cutoff_ms}"),
            ">=" => write!(self.sql, " >= {day_before_cutoff_ms}"),
            "<" => write!(self.sql, " < {day_before_cutoff_ms}"),
            "<=" => write!(self.sql, " < {target_cutoff_ms}"),
            "=" => write!(
                self.sql,
                " between {} and {}",
                day_before_cutoff_ms,
                target_cutoff_ms.0 - 1
            ),
            "!=" => write!(
                self.sql,
                " not between {} and {}",
                day_before_cutoff_ms,
                target_cutoff_ms.0 - 1
            ),
            _ => unreachable!("unexpected op"),
        }
        .unwrap();

        match ease {
            RatingKind::AnswerButton(u) => write!(self.sql, " and ease = {u})"),
            RatingKind::AnyAnswerButton => write!(self.sql, " and ease > 0)"),
            RatingKind::ManualReschedule => write!(self.sql, " and ease = 0)"),
        }
        .unwrap();

        Ok(())
    }

    pub(super) fn write_prop(&mut self, op: &str, kind: &PropertyKind) -> Result<()> {
        let timing = self.col.timing_today()?;

        match kind {
            PropertyKind::Due(days) => {
                let day = days + (timing.days_elapsed as i32);
                write!(
                    self.sql,
                    // SQL does integer division if both parameters are integers
                    "(\
                    (c.queue in ({rev},{daylrn}) and
                        (case when c.odue != 0 then c.odue else c.due end) {op} {day}) or \
                    (c.queue in ({lrn},{previewrepeat}) and
                        (((case when c.odue != 0 then c.odue else c.due end) - {cutoff}) / 86400) {op} {days})\
                    )",
                    rev = CardQueue::Review as u8,
                    daylrn = CardQueue::DayLearn as u8,
                    op = op,
                    day = day,
                    lrn = CardQueue::Learn as i8,
                    previewrepeat = CardQueue::PreviewRepeat as i8,
                    cutoff = timing.next_day_at,
                    days = days
                ).unwrap()
            }
            PropertyKind::Position(pos) => write!(
                self.sql,
                "(c.type = {t} and (case when c.odue != 0 then c.odue else c.due end) {op} {pos})",
                t = CardType::New as u8,
                op = op,
                pos = pos
            )
            .unwrap(),
            PropertyKind::Interval(ivl) => write!(self.sql, "ivl {op} {ivl}").unwrap(),
            PropertyKind::Reps(reps) => write!(self.sql, "reps {op} {reps}").unwrap(),
            PropertyKind::Lapses(days) => write!(self.sql, "lapses {op} {days}").unwrap(),
            PropertyKind::Ease(ease) => {
                write!(self.sql, "factor {} {}", op, (ease * 1000.0) as u32).unwrap()
            }
            PropertyKind::Rated(days, ease) => self.write_rated(op, i64::from(*days), ease)?,
            PropertyKind::CustomDataNumber { key, value } => {
                write!(
                    self.sql,
                    "cast(extract_custom_data(c.data, '{key}') as float) {op} {value}"
                )
                .unwrap();
            }
            PropertyKind::CustomDataString { key, value } => {
                write!(
                    self.sql,
                    "extract_custom_data(c.data, '{key}') {op} '{value}'"
                )
                .unwrap();
            }
            PropertyKind::Stability(s) => {
                write!(self.sql, "extract_fsrs_variable(c.data, 's') {op} {s}").unwrap()
            }
            PropertyKind::Difficulty(d) => {
                let d = d * 9.0 + 1.0;
                write!(self.sql, "extract_fsrs_variable(c.data, 'd') {op} {d}").unwrap()
            }
            PropertyKind::Retrievability(r) => {
                let (elap, next_day_at, now) = {
                    let timing = self.col.timing_today()?;
                    (timing.days_elapsed, timing.next_day_at, timing.now)
                };
                const NEW_TYPE: i8 = CardType::New as i8;
                write!(
                    self.sql,
                    "case when c.type = {NEW_TYPE} then false else (extract_fsrs_retrievability(c.data, case when c.odue !=0 then c.odue else c.due end, c.ivl, {elap}, {next_day_at}, {now}) {op} {r}) end"
                )
                .unwrap()
            }
        }

        Ok(())
    }

    pub(super) fn write_custom_data(&mut self, key: &str) -> Result<()> {
        write!(self.sql, "extract_custom_data(c.data, '{key}') is not null").unwrap();
        Ok(())
    }

    pub(super) fn previous_day_cutoff(&mut self, days_back: u32) -> Result<TimestampSecs> {
        let timing = self.col.timing_today()?;
        Ok(timing.next_day_at.adding_secs(-86_400 * days_back as i64))
    }

    pub(super) fn write_added(&mut self, days: u32) -> Result<()> {
        let cutoff = self.previous_day_cutoff(days)?.as_millis();
        write!(self.sql, "c.id > {cutoff}").unwrap();
        Ok(())
    }

    pub(super) fn write_edited(&mut self, days: u32) -> Result<()> {
        let cutoff = self.previous_day_cutoff(days)?;
        write!(self.sql, "n.mod > {cutoff}").unwrap();
        Ok(())
    }

    pub(super) fn write_introduced(&mut self, days: u32) -> Result<()> {
        let cutoff = self.previous_day_cutoff(days)?.as_millis();
        write!(
            self.sql,
            concat!(
                "((SELECT coalesce(min(id) > {cutoff}, false) FROM revlog WHERE cid = c.id ",
                // Exclude manual reschedulings
                "AND ease != 0) ",
                // Logically redundant, speeds up query
                "AND c.id IN (SELECT cid FROM revlog WHERE id > {cutoff}))"
            ),
            cutoff = cutoff,
        )
        .unwrap();
        Ok(())
    }
}
