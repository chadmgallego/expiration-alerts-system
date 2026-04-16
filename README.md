# 📄 Document Expiration Alert System

An automated document expiration monitoring pipeline built for a field staff organization managing visa, passport, and residency documentation across multiple households. The system queries a cloud-hosted PostgreSQL database, applies a tiered alert logic, and delivers email notifications to household contacts — running on a cron schedule with zero manual intervention.

---

## 📋 Table of Contents

- [Project Overview](#project-overview)
- [Business Context & Impact](#business-context--impact)
- [Tech Stack](#tech-stack)
- [System Architecture](#system-architecture)
- [Alert Logic](#alert-logic)
- [Database Schema](#database-schema)
- [Setup & Configuration](#setup--configuration)
- [Limitations & Future Work](#limitations--future-work)
- [Repository Structure](#repository-structure)

---

## Project Overview

This project replaces a manual document tracking process with a fully automated alert pipeline. A Python script connects to a PostgreSQL database hosted on Supabase, identifies documents entering expiration windows, and sends grouped email alerts to household contacts — with smart deduplication logic to prevent alert fatigue.

The system enforces four alert tiers:

| Alert Tier | Window | Frequency |
|---|---|---|
| Expired | Past expiration date | Weekly (7-day cooldown) |
| 90-day | 61–90 days to expiration | Once |
| 60-day | 31–60 days to expiration | Once |
| 30-day (URGENT) | 0–30 days to expiration | Weekly (7-day cooldown) |

A cron job runs the script every 6 hours, ensuring alerts fire within a day of becoming due regardless of laptop uptime.

---

## Business Context & Impact

Staff and dependents at field organizations frequently hold time-sensitive documents — visas, residence cards, passports, and work permits — that require renewal on strict government deadlines. Missed renewals carry legal and operational consequences.

This system was built to eliminate manual tracking overhead and ensure no document renewal window is missed:

- **Tiered alerts** give households 90, 60, and 30 days of advance notice — enough lead time to initiate renewal processes in high-bureaucracy environments
- **Weekly reminders** in the 30-day window keep urgent documents visible without requiring manual follow-up
- **Expired document tracking** flags and re-alerts on documents past their expiration date on a weekly cadence until renewed
- **Grouped emails** consolidate all expiring documents per household into a single notification, reducing inbox noise
- **Priority subject lines** escalate from standard → URGENT → ACTION REQUIRED based on the most critical document in each email batch

---

## Tech Stack

| Category | Tools |
|---|---|
| **Language** | Python 3.13 |
| **Database** | PostgreSQL (Supabase) |
| **Database Driver** | `psycopg2` |
| **Data Processing** | `pandas` |
| **Email** | `smtplib`, `EmailMessage` (Gmail SMTP over SSL) |
| **Scheduling** | macOS cron (`crontab`) |
| **Credentials Management** | `python-dotenv`, environment variables |
| **Version Control** | Git, GitHub |

---

## System Architecture

```
cron (every 6 hours)
      │
      ▼
src/expiration_alerts.py
  ├── psycopg2 → Supabase PostgreSQL
  │     └── Four-tier WHERE clause filters qualifying documents
  │
  ├── pandas
  │     ├── should_send() — returns 'expired', 30, 60, or 90
  │     ├── build_line() — formats document lines (expired vs. days remaining)
  │     └── Groups documents by household email
  │
  ├── smtplib (Gmail SMTP, port 465)
  │     └── Sends one email per household contact
  │     └── Subject: ACTION REQUIRED > URGENT > standard
  │
  └── psycopg2 (UPDATE)
        ├── Expired docs: sets expired = TRUE, stamps last_alert_sent
        └── Active docs: stamps last_alert_sent and last_alert_type
```

---

## Alert Logic

The SQL `WHERE` clause gates which documents qualify for alerts on each run:

```sql
WHERE 
    -- Expired window: past expiration date, alert every 7 days
    (
        d.expiration_date < CURRENT_DATE
        AND (
            d.last_alert_sent IS NULL
            OR d.last_alert_sent <= CURRENT_DATE - INTERVAL '7 days'
        )
    )
    -- 30-day window: weekly, enforced by 7-day cooldown on last_alert_sent
    OR (
        (d.expiration_date - CURRENT_DATE) >= 0
        AND (d.expiration_date - CURRENT_DATE) <= 30
        AND (
            d.last_alert_sent IS NULL
            OR d.last_alert_sent <= CURRENT_DATE - INTERVAL '7 days'
        )
    )
    -- 60-day window: fires once, only if stepping down from 90-day alert or fresh
    OR (
        (d.expiration_date - CURRENT_DATE) > 30
        AND (d.expiration_date - CURRENT_DATE) <= 60
        AND (d.last_alert_type = 90 OR d.last_alert_type IS NULL)
    )
    -- 90-day window: fires once, only if never alerted before
    OR (
        (d.expiration_date - CURRENT_DATE) > 60
        AND (d.expiration_date - CURRENT_DATE) <= 90
        AND d.last_alert_type IS NULL
    )
```

After each successful send, the script updates `last_alert_sent`, `last_alert_type`, and `expired` per document — preventing duplicate alerts across runs.

---

## Database Schema

```sql
CREATE TABLE HOUSEHOLD_CONTACTS (
    household_contact_id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    email TEXT NOT NULL
);

CREATE TABLE STAFF_AND_DEP (
    personal_id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    household_contact_id INTEGER REFERENCES HOUSEHOLD_CONTACTS(household_contact_id)
);

CREATE TABLE DOCUMENTS (
    document_id SERIAL PRIMARY KEY,
    personal_id INTEGER REFERENCES STAFF_AND_DEP(personal_id),
    document_type TEXT,
    expiration_date DATE,
    last_alert_sent DATE,
    last_alert_type INTEGER,        -- stores 30, 60, or 90 depending on last alert tier sent
    expired BOOLEAN DEFAULT FALSE,  -- set to TRUE when expiration_date < CURRENT_DATE
    CONSTRAINT unique_person_document UNIQUE (personal_id, document_type)
);
```

Full schema available in [`sql/schema.sql`](sql/schema.sql).

---

## Setup & Configuration

**1. Clone the repo and install dependencies:**
```bash
git clone https://github.com/chadmgallego/expiration-alerts-system.git
cd expiration-alerts-system
pip install -r requirements.txt
```

**2. Create a `.env` file in the project root:**
```
DB_HOST=your-supabase-host
DB_USER=your-db-user
DB_PASSWORD=your-db-password
GMAIL_SENDER=your-gmail@gmail.com
GMAIL_APP_PASSWORD=your-gmail-app-password
```

**3. Set up the cron job:**
```bash
crontab -e
```
Add:
```
0 */6 * * * cd "/path/to/expiration-alerts-system" && /usr/bin/python3 src/expiration_alerts.py
```

**4. Adding new households:**

New households are onboarded via a Google Form collecting each family member's name and document expiration dates. After a form submission, use [`sql/household_intake_template.sql`](sql/household_intake_template.sql) as a reusable upsert template to load the data into PostgreSQL. The template follows a three-step order — `HOUSEHOLD_CONTACTS` → `STAFF_AND_DEP` → `DOCUMENTS` — includes deduplication checks to prevent duplicate records, and includes a verification query to confirm all inserts before closing out the submission.

---

## Limitations & Future Work

**Current limitations:**
- Requires local machine to be awake — cron runs on laptop, not a persistent cloud server
- Gmail SMTP only — no support for other email providers
- No web UI for managing documents — all data entry done directly in the database
- Google Form submissions require manual SQL inserts — no automated ingestion pipeline

**Planned improvements:**
- Migrate cron scheduling to a cloud-native solution (AWS EventBridge + Lambda or equivalent) for fully serverless execution
- Automate Google Form → PostgreSQL ingestion using Google Apps Script or a webhook
- Add a lightweight admin UI for non-technical staff to manage document records without direct database access
- Expand notification channels (SMS via Twilio, Slack alerts)
- Add logging and alerting for failed email sends

---

## Repository Structure

```
expiration-alerts-system/
├── sql/
│   ├── schema.sql                     # PostgreSQL table definitions
│   ├── alert_query.sql                # Four-tier alert WHERE clause
│   └── household_intake_template.sql  # Reusable upsert template for new family submissions
├── src/
│   └── expiration_alerts.py           # Main pipeline script
├── requirements.txt                   # Python dependencies
├── .gitignore                         # Excludes .env, database files, build artifacts
└── README.md
```

---

*Built for internal use at a field staff organization managing multinational document compliance. All credentials managed via environment variables — no sensitive data in source control.*
