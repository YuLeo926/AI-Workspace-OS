# Handoff TTL

A handoff should be short-lived enough to bootstrap the next session.

It should not become a daily log, a full project archive, or a substitute for ADRs and ops logs.

## Good Handoff Content

- current role;
- workspace boundary;
- required reading order;
- hard constraints;
- current state;
- next step;
- pending decisions.

## Bad Handoff Content

- long chronological history;
- every action from the previous week;
- duplicated rules;
- unresolved debates that should be ADRs;
- raw logs or private data.

## Review Rule

During weekly review, shrink the handoff back to bootstrapping content. Move durable decisions to ADRs, audit events to ops logs, and priorities to `00_THIS_WEEK.md`.
