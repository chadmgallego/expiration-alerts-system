import smtplib, sys, os
from email.message import EmailMessage
from dotenv import load_dotenv
import psycopg2
import pandas as pd
from datetime import date

# Load environment variables from .env file (keeps credentials out of source code)
load_dotenv()

pd.set_option('display.max_rows', None)
pd.set_option('display.max_columns', None)

def main():
    # Connect to Supabase Postgres via Session Pooler
    # Credentials loaded from .env locally, or Railway environment variables in production
    conn = psycopg2.connect(
        host=os.getenv("DB_HOST"),
        port="5432",
        database="postgres",
        user=os.getenv("DB_USER"),
        password=os.getenv("DB_PASSWORD")
    )

    # Pull all documents that fall into one of three alert windows:
    #   - <= 30 days: always alert (weekly cadence handled by scheduler)
    #   - 31-60 days: only if last alert was 90-day or no alert sent yet
    #   - 61-90 days: only if no alert has ever been sent
    query = """
    SELECT 
        s.name, 
        d.document_type, 
        d.expiration_date,
        h.email,
        (d.expiration_date - CURRENT_DATE) AS days_left,
        CASE 
            WHEN d.expiration_date <= CURRENT_DATE + INTERVAL '30 days' THEN 'URGENT!' 
            ELSE NULL 
        END AS urgency,
        d.last_alert_sent,
        d.last_alert_type,
        d.document_id
    FROM DOCUMENTS d 
    JOIN STAFF_AND_DEP s ON d.personal_id = s.personal_id
    JOIN HOUSEHOLD_CONTACTS h ON s.household_contact_id = h.household_contact_id
    WHERE 
        (
            (d.expiration_date - CURRENT_DATE) <= 30
        )
        OR (
            (d.expiration_date - CURRENT_DATE) > 30
            AND (d.expiration_date - CURRENT_DATE) <= 60
            AND (d.last_alert_type = 90 OR d.last_alert_type IS NULL)
        )
        OR (
            (d.expiration_date - CURRENT_DATE) > 60
            AND (d.expiration_date - CURRENT_DATE) <= 90
            AND d.last_alert_type IS NULL
        );
    """

    df = pd.read_sql_query(query, conn)

    # If no documents qualify for alerts today, exit early — nothing to send
    if len(df) == 0:
        print("No alerts to send today.")
        conn.close()
        return

    print("=== Raw query results ===")
    print(df.to_string())

    def should_send(row):
        """
        Determines which alert tier applies to a given document row.
        Returns 30, 60, or 90 depending on days_left and last_alert_type.
        Returns None if no alert should be sent (shouldn't happen after SQL filter,
        but kept as a safety net for boundary edge cases).
        """
        days = row['days_left']
        last_type = row['last_alert_type']

        # 30-day window: always send, every week
        if days <= 30:
            return 30
        # 60-day window: only send once, and only if stepping down from 90-day or fresh
        if 30 < days <= 60 and (pd.isna(last_type) or last_type == 90):
            return 60
        # 90-day window: only send once, never been alerted before
        if 60 < days <= 90 and pd.isna(last_type):
            return 90
        return None

    # Apply alert tier logic row-by-row, store result in new column
    df['current_alert_type'] = df.apply(should_send, axis=1)

    print("\n=== Alerts to send ===")
    print(df.to_string())

    # Build the display line for each document — this is what appears in the email body
    df['line'] = (
        df['name'] + ' - ' +
        df['document_type'] +
        ' (Expires: ' +
        df['expiration_date'].astype(str) + ', ' +
        df['days_left'].astype(str) + ' days left' +
        # Only append urgency tag if the value is not null
        df['urgency'].apply(lambda u: f' {u}' if pd.notna(u) else '') +
        ')'
    )

    # Group rows by email address — one email per household contact
    # pd.Series is required here so pandas expands the dict keys into separate columns
    # (returning a plain dict would store the whole dict as a single scalar per row)
    messages = (
        df.groupby('email')
        .apply(lambda g: pd.Series({
            'message': '\n'.join(g['line']),          # combine all document lines into one block
            'has_urgent': g['urgency'].notna().any()  # True if any doc in this group is URGENT
        }))
        .reset_index()
    )

    # Credentials loaded from .env locally, Railway environment variables in production
    sender = os.getenv("GMAIL_SENDER")
    app_password = os.getenv("GMAIL_APP_PASSWORD")
    today = date.today().isoformat()  # e.g. "2025-04-08" — used to update last_alert_sent in DB

    # --- Send one email per household contact ---
    for _, row in messages.iterrows():
        receiver = row['email']

        # Subject line gets URGENT prefix if any document in this batch is within 30 days
        subject = "URGENT: Documents Expiring Soon!" if row['has_urgent'] else "Documents Expiring Soon!"

        print(f"\nSending to: {receiver} | Subject: {subject}")
        print(row['message'])

        email_msg = EmailMessage()
        email_msg['Subject'] = subject
        email_msg['From'] = sender
        email_msg['To'] = receiver
        email_msg.set_content(
            f"The following documents require your attention:\n\n{row['message']}\n\n"
            f"Please take action to renew these documents before they expire."
        )

        # SMTP_SSL opens an encrypted connection on port 465 — login and send
        try:
            with smtplib.SMTP("smtp.gmail.com", 587) as smtp:
                smtp.ehlo()
                smtp.starttls()
                smtp.login(sender, app_password)
                smtp.send_message(email_msg)
            print("Email sent!")
        except Exception as e:
            print(f"Email failed: {e}")

    # --- Update the database after emails are sent ---
    cursor = conn.cursor()

    # .values.tolist() returns a list of lists: [[doc_id, alert_type], ...]
    updates = df[['document_id', 'current_alert_type']].values.tolist()

    for doc_id, alert_type in updates:
        # Stamp each alerted document with today's date and the alert tier that was sent
        cursor.execute("""
            UPDATE DOCUMENTS
            SET last_alert_sent = %s,
                last_alert_type = %s
            WHERE document_id = %s
        """, (today, int(alert_type), int(doc_id)))

    conn.commit()
    print(f"\nDB updated: {len(updates)} document(s) updated.")

    conn.close()


if __name__ == "__main__":
    main()